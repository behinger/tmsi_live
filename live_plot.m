
%%
% It is sometimes helpful to see the non-referenced signal (measured against ground) to check for common mode issues
reference_on = false
% Step 1: Setup library and choose connection type ( 'usb', 'bluetooth', 'network' or 'wifi' ).
library = TMSi.Library('usb');

% Step 2: Find device to connect to. Keep on trying every second.
while numel(library.devices) == 0
    library.refreshDevices();
    pause(1);
end


% Step 3: Get first device an retrieve information about device.
device = library.getFirstDevice();

% Step 4: Create a sampler with which we are going to retrieve samples.
sampler = device.createSampler();

% Step 5: Set settings for sampler.
sampler.setSampleRate(128);



% Step 6: Connect to device through the sampler.
sampler.connect();

sampler.setReferenceCalculation(reference_on)


tic;
sampler.start();

% If you want to record while watching uncomment this
filename = 'tempRecording'
% poly5 = TMSi.Poly5(filename, filename, sampler.sample_rate, device.channels);

%this requires eeglab
EEG = eeg_emptyset;
EEG.srate = sampler.sample_rate;

% what channels are EEG?
eegChan = find(cellfun(@(x)x.type==1,sampler.device.channels));
chanNum = length(eegChan);

% Open up the figure
figure,
% specify the data, we want 60s of data

lSmooth = zeros(EEG.srate*60,chanNum);
l = lSmooth;
data_raw = lSmooth;
x = 1:size(lSmooth,1); %could be improved to show actual time
h = {};


for i =1:chanNum

	% During testing we sometimes replaced few chanels, so this is an option to color them
    chI = mod(i-1,64)+1;
    if chI <5
        color='b';
    elseif chI < 17
        color = 'b';
    elseif chI < 33
        color = 'r';
    elseif chI < 49
        color = 'k';
    elseif chI <=64
        color = 'g';
    end
	
	% make different subplot for each linked ampifier
    if i<=64
        subplot(2,1,1)
        
    else
        subplot(2,1,2)
%         color=[color ':'];
    end
    
	% I'm using a trick here
	% first I plot the data
    h{i} = plot(x,lSmooth(:,chanNum),color);
    hold all
	% now I need to tell datasource, because I have different lines I need a separate variable for each!
	% Therefore I later create the lSmooth1,lSmooth2,lSmooth3 etc. variables
    h{i}.YDataSource = sprintf('lSmooth%i',i);
    h{i}.XDataSource = 'x';
end

%%
% Should we calculate average reference on the data?
% this takes the link cable we have into account
avgref = true;

% I forgot why I choose these number
filtOrd = 4*400; % min samples to filter over

while true
	%we are online!
    fprintf('sampling...')
    samples = sampler.sample(); %tmsi function
    %     poly5.append(samples); %if you want to save the samples
    
    d = double(samples(eegChan,:)); 
    if avgref
        if chanNum > 65
			% we have two amplifiers,
			% first we take the reference over each amplifier - but we need to exclude channels which are not plugged in
            takeThese = find(any(d~=0,2));
            takeThese = takeThese(takeThese<65);
            d(takeThese,:) = bsxfun(@minus,d(takeThese,:),mean(d(takeThese,:),1));
            takeThese = find(any(d~=0,2));
            takeThese = takeThese(takeThese>=65);
            d(takeThese,:) = bsxfun(@minus,d(takeThese,:),mean(d(takeThese,:),1));
        else
		% one amplifier is easy
		% XXX I did not include empty channels here
         d = bsxfun(@minus,d,mean(d,1));
        end
        
         
         
		% In case we want common reference uncomment these (needs the link cable)
%          d(1:64,:) = bsxfun(@minus,d(1:64,:),d(16,:));
%          d(65:128,:) = bsxfun(@minus,d(65:128,:),d(105,:));
    end
	
    n_samples = size(d,2);
    fprintf(' %i new samples found\n',n_samples)

	% There ought to be a better way, but this is my First In last Out stack
    % shift the raw data
    data_raw(1:end-n_samples,:) = data_raw((1+n_samples):end,:);
    % add the new data
    data_raw((end-n_samples)+1:end,:) = d';
    
    % get a subset of raw data from the end to filter
    EEG.data = data_raw(end-max(n_samples,filtOrd)+1:end,:)';
    EEG.times = [];
    EEG.xmax = size(EEG.data,2)/EEG.srate;
    EEG.pnts = size(EEG.data,2);
    EEG = eeg_checkset(EEG);
    tic
	
	% We want to filter at 16Hz
    f = 16;
    EEGtmp = pop_eegfiltnew(EEG, (f+2/3)-0.5,(f+2/3)+0.5,400,0,[],0);
    
	% and at 20Hz as a control
    f = 20;
    EEGtmp2 = pop_eegfiltnew(EEG, (f)-0.5,(f)+0.5,400,0,[],0);
    toc
	
	% Maybe 50 Hz?
%     EEGtmp = pop_eegfiltnew(EEG, (50)-5,50+5,420,0,[],0);
	
	% Calculate the envelope activity of the filtered signal - in this case I normalize the 16Hz by the 20Hz
    l(1:(end-n_samples),:) = l((n_samples+1):(end),:);
	
	% Not sure why I did this
    EEGtmp2.data(EEGtmp2.data<eps) = -1;
    l((end-max(n_samples,filtOrd)+1):end,:) = envelope(EEGtmp.data(:,:)',400,'rms') ./ envelope(EEGtmp2.data(:,:)',400,'rms');
    toc
    
    
    % We redefine x because size of the stack can change
    x = 1:size(lSmooth,1);
	
	% We update the plot data
    for i = 1:chanNum
        if any(l(:,i),1)~=0
        eval(sprintf('lSmooth%i = l(:,%i);',i,i));
        end
    end
    toc
	% change some limits
    subplot(2,1,1)
    ylim([0 20])
    subplot(2,1,2)
    ylim([0 100])
	%refresh everything that changed!
    refreshdata(h(any(l(:,:),1) ~= 0))
    drawnow
    toc
end