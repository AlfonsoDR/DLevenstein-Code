function [SpikeLFPCoupling] = bz_GenSpikeLFPCoupling(spiketimes,LFP,varargin)
% SpikeLFPCoupling = GenSpikeLFPCoupling(spiketimes,LFP)
%
%INPUT
%   spiketimes          {Ncells} cell array of spiketimes for each cell
%                       -or- TSObject
%   LFP                 structure with fields (from bz_GetLFP)
%                           lfp.data
%                           lfp.timestamps
%                           lfp.samplingRate
%                       -or- [t x nchannels] vector 
%   (optional)
%       'sf_LFP'
%       'frange'
%       'tbin'
%       'waveparms'...
%       'nfreqs'
%       'int'
%       'ISIpower'      true: calculate mutual information between power
%                       ISI distribution
%       'cellLFPchannel'  The local LFP channel associated with each cell (if
%                       sites are in different electroanatomical regions)
%       'cellsort'        'pca','none','sortf','sortorder','celltype','rate'
%       'controls'        'thinspikes','jitterspikes','shufflespikes'
%       'downsample'
%       'subpop'        %DL: update this... to buzcode
%       'jittersig'     true/false for jittered spikes significance
%       'showFig'       true/false
%
%OUTPUT
%        SpikeLFPCoupling
%           .freqs
%           .pop
%               .popcellind
%               .cellpopidx
%           .cell
%               .ratepowercorr
%               .ratepowersig
%               .spikephasemag
%               .spikephaseangle
%               .spikephasesig
% 
%           .detectorinfo
%               .detectorname
%               .detectiondate
%               .detectionintervals
%               .detectionchanne;
%
%TO DO
%   -Put synch/spikerate in same section
%   -multiple ints - this (along with controls) will require making
%   subfunctions to loop
%   -clean and buzcode
%
%DLevenstein 2016
%% inputParse for Optional Inputs and Defaults
p = inputParser;

defaultSf = 1250;

defaultInt = [0 Inf];
checkInt = @(x) size(x,2)==2 && isnumeric(x) || isa(x,'intervalSet');

defaultNfreqs = 100;
defaultNcyc = 5;
defaultFrange = [1 128];
%validFranges = {'delta','theta','spindles','gamma','ripples'};
%checkFrange = @(x) any(validatestring(x,validFranges)) || size(x) == [1,2];
checkFrange = @(x) isnumeric(x) && length(x(1,:)) == 2 && length(x(:,1)) == 1;

defaultSynchdt = 0.005;
defaultSynchwin = 0.02;

defaultSorttype = 'rate';
validSorttypes = {'pca','none','sortf','sortorder','celltype','rate'};
checkSorttype = @(x) any(validatestring(x,validFranges)) || size(x) == [1,2];

defaultDOWN = false;

addParameter(p,'sf_LFP',defaultSf,@isnumeric)
addParameter(p,'int',defaultInt,checkInt)
addParameter(p,'frange',defaultFrange,checkFrange)
addParameter(p,'nfreqs',defaultNfreqs,@isnumeric)
addParameter(p,'ncyc',defaultNcyc,@isnumeric)
addParameter(p,'synchdt',defaultSynchdt,@isnumeric)
addParameter(p,'synchwin',defaultSynchwin,@isnumeric)
addParameter(p,'sorttype',defaultSorttype,checkSorttype)
addParameter(p,'DOWNSAMPLE',defaultDOWN,@isnumeric)
addParameter(p,'subpop',0)
addParameter(p,'channel',[])
addParameter(p,'jittersig',false)
addParameter(p,'showFig',true)
addParameter(p,'saveFig',false)
addParameter(p,'saveMat',false)
addParameter(p,'ISIpower',false)

parse(p,varargin{:})
%Clean up this junk...
sf_LFP = p.Results.sf_LFP;
int = p.Results.int;
nfreqs = p.Results.nfreqs;
frange = p.Results.frange;
ncyc = p.Results.ncyc;
synchdt = p.Results.synchdt;
subpop = p.Results.subpop;
jittersig = p.Results.jittersig;
SHOWFIG = p.Results.showFig;
SAVEMAT = p.Results.saveMat;
figfolder = p.Results.saveFig; 
usechannel = p.Results.channel; 
ISIpower = p.Results.ISIpower; 

%% Deal with input types

%Spiketimes can be: tsdArray of cells, cell array of cells, cell array of
%tsdArrays (multiple populations)
if isa(spiketimes,'tsdArray')
    numcells = length(spiketimes);
    for cc = 1:numcells
        spiketimestemp{cc} = Range(spiketimes{cc},'s');
    end
    spiketimes = spiketimestemp;
    clear spiketimestemp
elseif isa(spiketimes,'cell') && isa(spiketimes{1},'tsdArray')
    numpop = length(spiketimes);
    lastpopnum = 0;
    for pp = 1:numpop
        if length(spiketimes{pp})==0
            spiketimes{pp} = {};
            popcellind{pp} = [];
            continue
        end
        for cc = 1:length(spiketimes{pp})
            spiketimestemp{cc} = Range(spiketimes{pp}{cc},'s');
        end
        spiketimes{pp} = spiketimestemp;
        popcellind{pp} = [1:length(spiketimes{pp})]+lastpopnum;
        lastpopnum = popcellind{pp}(end);
        clear spiketimestemp
    end
    spiketimes = cat(2,spiketimes{:});
    numcells = length(spiketimes);
    subpop = 'done';
elseif isa(spiketimes,'cell')
    numcells = length(spiketimes);
end

if isa(int,'intervalSet')
    int = [Start(int,'s'), End(int,'s')];
end

%LFP Input
if ~isstruct(LFP)
    t_LFP = (1:length(LFP))'/sf_LFP;
end

if ~isempty(usechannel)
    usechannel = ismember(LFP.channels,usechannel);
    LFP.data = LFP.data(:,usechannel);
end

%Downsampling
if p.Results.DOWNSAMPLE
    assert((LFP.samplingRate/p.Results.DOWNSAMPLE)>2*max(frange),'downsample factor is too big...')    
    [ LFP ] = bz_DownsampleLFP(LFP,p.Results.DOWNSAMPLE);
end
%% Subpopulations
if isequal(subpop,0)
        numpop = 1;
        popcellind = {1:numcells};
elseif isequal(subpop,'done')
else
        pops = unique(subpop);
        numpop = length(pops);
        for pp = 1:numpop
            popcellind{pp} = find(subpop == pops(pp));
        end
end

cellpopidx = zeros(1,numcells);


%% Calculate spike matrix
overlap = p.Results.synchwin/synchdt;
spikemat = bz_SpktToSpkmat(spiketimes,'binsize',p.Results.synchwin,'overlap',overlap);

inint = InIntervals(spikemat.timestamps,int);
spikemat.data = spikemat.data(inint,:);
spikemat.timestamps = spikemat.timestamps(inint);


%% Calculate ISIs (if needed), Apply interval/spike number limits here

%Take only spike times in intervals
spiketimes_int = cellfun(@(X) X(InIntervals(X,int)),spiketimes,'UniformOutput',false);

if ISIpower
    %Calculate (pre/postceding ISI) for each spike
    ISIs_prev = cellfun(@(X) [nan; diff(X)],spiketimes,'UniformOutput',false);
    ISIs_next = cellfun(@(X) [diff(X); nan],spiketimes,'UniformOutput', false);
    ISIs_prev_int = cellfun(@(X,Y) X(InIntervals(Y,int)),ISIs_prev,spiketimes,'UniformOutput',false);
    ISIs_next_int = cellfun(@(X,Y) X(InIntervals(Y,int)),ISIs_next,spiketimes,'UniformOutput',false);
end

% spikes.inint = cellfun(@(X) InIntervals(X,ints),spikes.times,'UniformOutput',false);
% 
% %Apply spikelimit here
% spikes.toomany = cellfun(@(X) (sum(X)-spikeLim).*((sum(X)-spikeLim)>0),spikes.inint);
% spikes.numcells = length(spikes.times);
% for cc = 1:spikes.numcells
%     spikes.inint{cc}(randsample(find(spikes.inint{cc}),spikes.toomany(cc)))=false;
% end
% 
% spikes.times = cellfun(@(X,Y) X(Y),spikes.times,spikes.inint,'UniformOutput',false);

%% Processing LFP - filter etc

%HERE: loop channels
for cc = 1:length(LFP.channels)
    chanID = LFP.channels(cc);

    switch nfreqs  
        case 1
            %Single frequency band - filter/hilbert
            filtered = bz_Filter(LFP,'passband',frange,'order',ncyc,'filter','fir1');
            LFP_filt = filtered.hilbert; 
            t_LFP = filtered.timestamps;
            freqs = [];
            clear filtered

            inint = InIntervals(t_LFP,int);
            LFP_filt = LFP_filt(inint,:);
            t_LFP = t_LFP(inint);

            %Normalize Power to Mean Power
            LFP_filt = LFP_filt./mean(abs(LFP_filt));

        otherwise
            %Multiple frequencies: Wavelet Transform
            wavespec = bz_WaveSpec(LFP,'intervals',int,'showprogress',true,'ncyc',ncyc,...
                'nfreqs',nfreqs,'frange',frange,'chanID',chanID);
            LFP_filt = wavespec.data;  
            t_LFP = wavespec.timestamps;
            freqs = wavespec.freqs;
            clear wavespec

            %Normalize power to mean power for each frequency
            LFP_filt = bsxfun(@(X,Y) X./Y,LFP_filt,nanmean(abs(LFP_filt),1));
    end

    %Get Power/Phase at each spike matrix time point 
    power4synch = interp1(t_LFP,abs(LFP_filt),spikemat.timestamps,'nearest');
    phase4synch = interp1(t_LFP,angle(LFP_filt),spikemat.timestamps,'nearest');

    %% Population Synchrony: Phase Coupling and Rate Modulation
    for pp = 1:numpop
        if length(popcellind{pp}) == 0
            synchcoupling(pp).powercorr = [];
            synchcoupling(pp).phasemag = [];
            synchcoupling(pp).phaseangle = [];
            numpop = numpop-1;
            continue
        end
        cellpopidx(popcellind{pp}) = pp;
        numpopcells = length(popcellind{pp});
        popsynch = sum(spikemat.data(:,popcellind{pp})>0,2)./numpopcells;
        popsynch = popsynch./mean(popsynch);

        %Calculate Synchrony-Power Coupling as correlation between synchrony and power
        [synchcoupling(pp).powercorr(:,cc)] = corr(popsynch,power4synch,'type','spearman','rows','complete');

        %Synchrony-Phase Coupling (magnitude/angle of power-weighted mean resultant vector)
        resultvect = nanmean(power4synch.*bsxfun(@(popmag,ang) popmag.*exp(1i.*ang),popsynch,phase4synch),1);
        synchcoupling(pp).phasemag(:,cc) = abs(resultvect);
        synchcoupling(pp).phaseangle(:,cc) = angle(resultvect);
   
    end

    %% Cell Rate-Power Modulation

    %Spike-Power Coupling
    [ratepowercorr(:,:,cc),ratepowersig(:,:,cc)] = corr(spikemat.data,power4synch,'type','spearman','rows','complete');
    clear power4synch 
    clear phase4synch

    %% Cell Spike-Phase Coupling
    
    %Find filtered LFP at the closest LFP timepoint to each spike.
    spkLFP_int = cellfun(@(X) interp1(t_LFP,LFP_filt,X,'nearest'),spiketimes_int,'UniformOutput',false);
    
    
    [spikephasemag_cell,spikephaseangle_cell] = cellfun(@(X,Y) spkphase(X,Y),spiketimes_int,spkLFP_int,...
        'UniformOutput',false);
    spikephasemag(:,:,cc) = cat(1,spikephasemag_cell{:});
    spikephaseangle(:,:,cc) = cat(1,spikephaseangle_cell{:});

    if jittersig
        %Jitter for Significane
        numjitt = 100;
        jitterwin = 2/frange(1);

        jitterbuffer = zeros(numcells,nfreqs,numjitt);
        for jj = 1:numjitt
            if mod(jj,10) == 1
                display(['Jitter ',num2str(jj),' of ',num2str(numjitt)])
            end
            jitterspikes = JitterSpiketimes(spiketimes,jitterwin);
            phmagjitt = cellfun(@(X) spkphase(X),jitterspikes,'UniformOutput',false);
            jitterbuffer(:,:,jj) = cat(1,phmagjitt{:});
        end
        jittermean = mean(jitterbuffer,3);
        jitterstd = std(jitterbuffer,[],3);
        spikephasesig(:,:,cc) = (spikephasemag-jittermean)./jitterstd;
    end
    %% Example Figure : Phase-Coupling Significance
    % cc = 6;
    % figure
    %     hist(squeeze(jitterbuffer(cc,:,:)),10)
    %     hold on
    %     plot(spikephasemag(cc).*[1 1],get(gca,'ylim')./4,'r','LineWidth',2)
    %     plot(spikephasemag(cc),get(gca,'ylim')./4,'ro','LineWidth',2)
    %     xlabel('pMRL')
    %     ylabel('Number of Jitters')
    %     xlim([0 0.2])

    %% Calculate mutual information between ISI distribution and power
    
    if ISIpower
        for nn = 1:length(spiketimes)
            bz_Counter(nn,length(spiketimes),'Cell')
            [totmutXPow(nn,:,cc)] = ISIpowerMutInf(ISIs_prev_int{nn},ISIs_next_int{nn},spkLFP_int{nn});
        end
        
    end
end

clear LFP_filt

%% Output

SpikeLFPCoupling.freqs = freqs;
SpikeLFPCoupling.pop = synchcoupling;
%SpikeLFPCoupling.pop.popcellind = popcellind; %update to match buzcode cell class input
%SpikeLFPCoupling.pop.cellpopidx = cellpopidx;
SpikeLFPCoupling.cell.ratepowercorr = ratepowercorr;
SpikeLFPCoupling.cell.ratepowersig = ratepowersig;
SpikeLFPCoupling.cell.spikephasemag = spikephasemag;
SpikeLFPCoupling.cell.spikephaseangle = spikephaseangle;
if ISIpower
    SpikeLFPCoupling.cell.ISIpowermodulation = totmutXPow;
end
if exist('spikephasesig','var')
    SpikeLFPCoupling.cell.spikephasesig = spikephasesig;
end

SpikeLFPCoupling.detectorinfo.detectorname = 'bz_GenSpikeLFPCoupling';
SpikeLFPCoupling.detectorinfo.detectiondate = datetime('today');
SpikeLFPCoupling.detectorinfo.detectionintervals = int;
SpikeLFPCoupling.detectorinfo.detectionchannel = LFP.channels;

if SAVEMAT
    save(savefile,'SpikeLFPCoupling')
end

%% Figure
if SHOWFIG
    
    %Sorting (and other plot-related things)
    switch p.Results.sorttype
        case 'pca'
            [~,SCORE,~,~,EXP] = pca(cellpower);
            [~,spikepowersort] = sort(SCORE(:,1));

            [~,SCORE,~,~,EXP_phase] = pca(cellphasemag);
            [~,spikephasesort] = sort(SCORE(:,1));
            sortname = 'PC1';
        case 'none'
            spikepowersort = 1:numcells;
        case 'fsort'
            fidx = interp1(freqs,1:nfreqs,sortf,'nearest'); 
            [~,spikepowersort] = sort(cellpower(:,fidx));
            [~,spikephasesort] = sort(cellphasemag(:,fidx));
            sortname = [num2str(sortf) 'Hz Magnitude'];
        case 'rate'
            spkrt = cellfun(@length,spiketimes);
            [~,spikepowersort] = sort(spkrt);
            spikephasesort = spikepowersort;
            sortname = 'Firing Rate';
        otherwise
            spikepowersort = sortidx;
    end
    
    
    
    switch nfreqs  
        case 1
    %% Figure: 1 Freq Band
    figure
        subplot(3,2,1)
            hold on
            hist(ratepowercorr)
            for pp = 1:numpop
                plot([synchcoupling(pp).powercorr,synchcoupling(pp).powercorr],...
                    get(gca,'ylim'))
            end
            xlabel('Rate-Power Correlation')
            title('Rate-Power Coupling')
            ylabel('# Cells')
        subplot(3,2,[2 4])
            for pp = 1:numpop
                polar(spikephaseangle(popcellind{pp}),(spikephasemag(popcellind{pp})),'o')
                hold on
                polar([0 synchcoupling(pp).phaseangle],[0 synchcoupling(pp).phasemag])

            end
            title('Spike-Phase Coupling')
        subplot(3,2,3)
            for pp = 1:numpop
                hold on
                plot(ratepowercorr(popcellind{pp}),(spikephasemag(popcellind{pp})),'o')
                plot(synchcoupling(pp).powercorr,synchcoupling(pp).phasemag,'*')
            end
            %LogScale('y',10)
            xlabel('Rate-Power Correlation')
            ylabel('Spike-Phase Coupling Magnitude')
        
        if figfolder
           NiceSave('SpikeLFPCoupling',figfolder,[]) 
        end
        otherwise
    %% Figure: Spectrum
    posnegcolor = makeColorMap([0 0 0.8],[1 1 1],[0.8 0 0]);

    figure
        subplot(3,2,1)
            hold on
            for pp = 1:numpop
                plot(log2(freqs),synchcoupling(pp).powercorr)
            end
            plot(log2(freqs([1 end])),[0 0],'k--')
            axis tight
            box off
            LogScale('x',2)
            title('Pop. Synchrony - Power Correlation')
            xlabel('f (Hz)');ylabel('rho')

    %     subplot(3,2,3)
    %         hold on
    %             [hAx,hLine1,hLine2] = plotyy(log2(freqs),cat(1,synchcoupling.phasemag),...
    %                 log2(freqs),mod(cat(1,synchcoupling.phaseangle),2*pi))
    %         LogScale('x',2)
    %         hLine1.LineStyle = 'none';
    %         hLine2.LineStyle = 'none';
    %         hLine1.Marker = 'o';
    %         hLine2.Marker = '.';
    %         title('Pop. Synchrony - Phase Coupling')
    %         xlabel('f (Hz)');
    %         ylabel(hAx(1),'Phase Coupling Magnitude')
    %         ylabel(hAx(2),'Phase Coupling Angle')

        subplot(3,2,3)
            hold on
            for pp = 1:numpop
                plot(log2(freqs),synchcoupling(pp).phasemag)
            end
            axis tight
            box off
            LogScale('x',2)
            title('Pop. Synchrony - Phase Coupling')
            xlabel('f (Hz)');
            ylabel('Phase Coupling Magnitude')
        subplot(3,2,5)
            hold on
            for pp = 1:numpop
                plot(log2(freqs),synchcoupling(pp).phaseangle,'o')
                plot(log2(freqs),synchcoupling(pp).phaseangle+2*pi,'o')
            end
            LogScale('x',2)
            title('Pop. Synchrony - Phase Coupling')
            xlabel('f (Hz)');
            axis tight
            box off
            ylim([-pi 3*pi])
            ylabel('Phase Coupling Angle')


        subplot(2,2,2)
            imagesc(log2(freqs),1:numcells,ratepowercorr(spikepowersort,:))
            xlabel('f (Hz)');ylabel(['Cell - Sorted by ',sortname])
            LogScale('x',2)
            title('Rate - Power Correlation')
            colormap(gca,posnegcolor)
            ColorbarWithAxis([-0.2 0.2],'rho')
        subplot(2,2,4)
            imagesc(log2(freqs),1:numcells,spikephasemag(spikephasesort,:))
            xlabel('f (Hz)');ylabel(['Cell - Sorted by ',sortname])
            title('Spike - Phase Coupling')
            LogScale('x',2)
            caxis([0 0.2])
            colorbar

        if figfolder
           NiceSave('SpikeLFPCoupling',figfolder,[]) 
        end

    end
end









    %% Spike-Phase Coupling function
    %takes spike times from a single cell and caluclates phase coupling magnitude/angle
    function [phmag,phangle] = spkphase(spktimes_fn,spkLFP_fn)
        %Spike Times have to be column vector
            if isrow(spktimes_fn); spktimes_fn=spktimes_fn'; end
            if isempty(spktimes_fn); phmag=nan;phangle=nan; return; end
        %Calculate (power normalized) resultant vector
        rvect = nanmean(abs(spkLFP_fn).*exp(1i.*angle(spkLFP_fn)),1);
        phmag = abs(rvect);
        phangle = angle(rvect);

        %% Example Figure : Phase-Coupling
        % if phmag >0.1
        % figure
        %         rose(phase4spike)
        %        % set(gca,'ytick',[])
        %         hold on
        %          polar(phase4spike,power4spikephase.*40,'k.')
        %         % hold on
        %          %compass([0 phangle],[0 phmag],'r')
        %          compass(rvect.*700,'r')
        %     delete(findall(gcf,'type','text'));
        %     % delete the text objects
        % end        
    end

    %% Power-ISI coupling function
    function [totmutXPow] = ISIpowerMutInf(prevISI,nextISI,spkLFP)
        powerbins = linspace(-0.5,0.5,10);
        logISIbins = linspace(-2.5,1,50);
        for ff = 1:size(spkLFP,2)
            allISIs = [prevISI;nextISI];
            allLFP = [spkLFP;spkLFP];

            joint = hist3([log10(allISIs) log10(abs(allLFP(:,ff)))],{logISIbins,powerbins});
            joint = joint./sum(joint(:));

            margX = hist(log10(allISIs),logISIbins);
            margX = margX./sum(margX);
            margPower = hist(log10(abs(allLFP(:,ff))),powerbins);
            margPower = margPower./sum(margPower);
            jointindependent =  bsxfun(@times, margX.', margPower);


            mutXPow = joint.*log2(joint./jointindependent); % mutual info at each bin
            totmutXPow(ff) = nansum(mutXPow(:)); % sum of all mutual information 
        end
        
        %% Example Figure: ISI-power modulation
%         figure
%         subplot(2,2,1)
%             imagesc(logISIbins,powerbins,joint')
%         subplot(2,2,2)
%             imagesc(logISIbins,powerbins,jointindependent')
        
    end
end
