function [ ccg,ccgt,shufflemean,shufflestd ] = CCGshuffle_CellID( spiketimes,shufftype,numshuff,CCGparms )
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here
%%

[ccg,ccgt] = CCG(spiketimes,[],'duration',0.5,'binSize',binsize);

ccg_shuff = zeros([size(ccg) numshuff]);
for ss = 1:numshuff
    ss
    switch shufftype
        case 'CellID'
            [ spiketimes_shuffle ] = ShuffleSpikelabels(spiketimes);
        case 'jitter'
             [ spiketimes_shuffle ] = JitterSpiketimes(spiketimes,jitterwin)
    end
    ccg_shuff(:,:,:,ss) = CCG(spiketimes_shuffle,[],'duration',0.5,'binSize',binsize);
end

shufflemean = mean(ccg_shuff,4);
shufflestd = std(ccg_shuff,[],4);
