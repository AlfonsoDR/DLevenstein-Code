function [ ISPCgram,lags ] = ISPCgram(signal1,signal2,wave_cyc,frange,nfreqs,win_cyc,dt,sf_sig)
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here
%
%
% sf    sampling frequency of the signel
% dt    desired output time step
%
%%Dependencies
%   WaveFilt
%   MorletWavelet
%   FConv
%
%
%Last Updated: 12/3/15
%DLevenstein
%%
if isempty(signal1)
    freqs=[]; t=[]; ISPCgram=signal1;
    return
end

if iscell(signal1)
    celllengths = cellfun(@length,signal1);
    signal1 = vertcat(signal1{:});
    signal2 = vertcat(signal2{:});
end




fmin = frange(1);
fmax = frange(2);
if strcmp(space,'log')
    freqs = logspace(log10(fmin),log10(fmax),nfreqs);
elseif strcmp(space,'lin')
    freqs = linspace(fmin,fmax,nfreqs);
else
    display('Frequency spacing must be "lin" or "log".')
end

t = (0:length(signal1)-1)*si;

ISPCgram = zeros(nfreqs,length(t));
phaselag = zeros(nfreqs,length(t));
for f_i = 1:nfreqs
    if mod(f_i,10) == 1;
        display(['freq ',num2str(f_i),' of ',num2str(nfreqs)]);
    end
    phase1 = angle(WaveFilt(signal1,freqs(f_i),wave_cyc,si));
    phase2 = angle(WaveFilt(signal2,freqs(f_i),wave_cyc,si));
    
    f_timewin = win_cyc*(1/freqs(f_i));
   
    [ISPCgram(f_i,:),phaselag(f_i,:)] = ISPCt(phase1,phase2,dt,f_timewin,sf_sig);
    
    
end

if exist('celllengths','var')
    ISPCgram = mat2cell(ISPC,nfreqs,celllengths);
end
    


end

