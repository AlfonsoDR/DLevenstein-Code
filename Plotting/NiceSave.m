function [  ] = NiceSave(figname,figfolder,recname,figtype)
%NiceSave(figname,figfolder,recname) formats the figure for best viewing
%and saves it as a .pdf in figfolder with name recname_figname.pdf
%
%DLevenstein Fall 2016
%%

if ~exist('figtype','var')
    figtype = 'pdf';
end

set(gcf,'PaperOrientation','landscape');
set(gcf,'PaperUnits','normalized');
set(gcf,'PaperPosition',[0 0 1 1]);
saveas(gcf,[figfolder,'/',recname,'_',figname],figtype) ;

end
