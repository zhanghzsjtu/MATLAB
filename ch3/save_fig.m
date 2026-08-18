function fpath = save_fig(fig, name, figdir)
% save_fig  统一保存 MATLAB 图到 figs 目录 (PNG, 150 dpi)
%   输入: fig    图句柄
%         name   文件名 (如 'ch3_fig3_3_recognition_df.png')
%         figdir 目录 (默认 '<脚本所在目录>/figs')

if nargin < 3 || isempty(figdir)
    figdir = fullfile(fileparts(mfilename('fullpath')), 'figs');
end
if ~exist(figdir, 'dir')
    mkdir(figdir);
end
fpath = fullfile(figdir, name);
exportgraphics(fig, fpath, 'Resolution', 150);

end
