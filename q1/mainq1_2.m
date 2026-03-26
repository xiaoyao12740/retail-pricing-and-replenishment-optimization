clear;
clc;
file='q1预处理1-2.xlsx';%文件名
sheet=1;%如有需要可改
dataRange='C4:H1091';%主数据区域（6列）
labelRange='C2:H2';%列名所在行
outdir=fullfile(pwd,'out_corr');
if ~exist(outdir,'dir'),mkdir(outdir);end
%读取列名与数据
try
    labelsCell=readcell(file,'Sheet',sheet,'Range',labelRange);
catch
    labelsCell={};
end
X=readmatrix(file,'Sheet',sheet,'Range',dataRange);
%剔除"整行全空"的年份分隔行
rowAllNaN=all(isnan(X),2);
X=X(~rowAllNaN,:);
%若还有全0行，也要剔除：
%X=X(~all(X==0,2),:);
%构造列名
if isempty(labelsCell)||all(cellfun(@(c)(isnumeric(c)&&isnan(c))||(isstring(c)&&strlength(c)==0)||(ischar(c)&&isempty(c)),labelsCell))
    n=size(X,2);
    labels=arrayfun(@(k)sprintf('Var%d',k),1:n,'UniformOutput',false);
else
    labels=cellfun(@(c)string(c),labelsCell,'UniformOutput',false);
end
n=size(X,2);
%若有个别单元是文本导致NaN，保持NaN，下面用pairwise处理
fprintf('有效行数：%d，变量数：%d\n',size(X,1),n);
%2)Spearman/Kendall/Pearson（原序列，按对删除缺失）
[R_s,P_s]=corr(X,'Type','Spearman','Rows','pairwise');
[R_k,P_k]=corr(X,'Type','Kendall','Rows','pairwise');
[R_p,P_p]=corr(X,'Type','Pearson','Rows','pairwise');
%多重比较（FDR）可选
adjP_s=fdr_mat(P_s);
adjP_k=fdr_mat(P_k);
adjP_p=fdr_mat(P_p);
%导出
write_matrix_with_labels(fullfile(outdir,'spearman_R.csv'),R_s,labels);
write_matrix_with_labels(fullfile(outdir,'spearman_p.csv'),P_s,labels);
write_matrix_with_labels(fullfile(outdir,'spearman_p_fdr.csv'),adjP_s,labels);
write_matrix_with_labels(fullfile(outdir,'kendall_R.csv'),R_k,labels);
write_matrix_with_labels(fullfile(outdir,'kendall_p.csv'),P_k,labels);
write_matrix_with_labels(fullfile(outdir,'kendall_p_fdr.csv'),adjP_k,labels);
write_matrix_with_labels(fullfile(outdir,'pearson_R.csv'),R_p,labels);
write_matrix_with_labels(fullfile(outdir,'pearson_p.csv'),P_p,labels);
write_matrix_with_labels(fullfile(outdir,'pearson_p_fdr.csv'),adjP_p,labels);
%热力图（Spearman）
draw_heatmap(R_s,labels,fullfile(outdir,'heatmap_spearman.png'),'Spearman 相关');
%一阶差分（稳健做法）
Xd=diff(X,1,1);%行方向做差
[R_sd,P_sd]=corr(Xd,'Type','Spearman','Rows','pairwise');
write_matrix_with_labels(fullfile(outdir,'spearman_R_diff.csv'),R_sd,labels);
draw_heatmap(R_sd,labels,fullfile(outdir,'heatmap_spearman_diff.png'),'Spearman（一阶差分）');
%偏相关（控制"六品类总和"）——近似"客流/共同冲击"去除
total=nansum(X,2);%总和
X_res=zeros(size(X));
for j=1:n
    y=X(:,j);
    mask=~(isnan(y)|isnan(total));
    if nnz(mask)>=3
        %对原值做OLS残差（也可对秩做回归当作"Spearman偏相关"）
        b=[ones(nnz(mask),1),total(mask)]\y(mask);
        r=y;r(mask)=y(mask)-[ones(nnz(mask),1),total(mask)]*b;
        X_res(:,j)=r;
    else
        X_res(:,j)=NaN;
    end
end
[R_partial,P_partial]=corr(X_res,'Type','Spearman','Rows','pairwise');
write_matrix_with_labels(fullfile(outdir,'spearman_partial_controlTotal_R.csv'),R_partial,labels);
draw_heatmap(R_partial,labels,fullfile(outdir,'heatmap_spearman_partial.png'),'Spearman 偏相关（控制总量）');
fprintf('结果已输出到：%s\n',outdir);
%end
%辅助函数
function write_matrix_with_labels(path,M,labels)
C=cell(numel(labels)+1);
C{1,1}='';
C(1,2:end)=labels;
C(2:end,1)=labels;
C(2:end,2:end)=num2cell(M);
writecell(C,path);
end
function draw_heatmap(R,labels,outpng,ttl)
f=figure('Visible','off');
h=heatmap(string(labels),string(labels),R,'Colormap',parula,'ColorLimits',[-1 1]);
title(ttl);%colorbar自动包含
set(gcf,'Position',[100 100 680 520]);
exportgraphics(f,outpng,'Resolution',150);
close(f);
end
function Adj=fdr_mat(P)
%对称矩阵P的Benjamini–Hochberg调整（只为便于浏览）
p=P(:);
nanmask=isnan(p);
p=p(~nanmask);
[~,~,adjp]=fdr_bh(p,0.05,'pdep');
Adj=NaN(size(P));
Adj(~nanmask)=adjp;
end
function [h,crit_p,adj_p]=fdr_bh(pvals,q,method)
%Benjamini & Hochberg FDR（简化版）
if nargin<2||isempty(q),q=0.05;end
if nargin<3||isempty(method),method='pdep';end
p=pvals(:);
[ps,idx]=sort(p);
m=numel(ps);
switch lower(method)
    case 'pdep',denom=(1:m)';%独立/正相关
    case 'dep',denom=(1:m)'*sum(1./(1:m));%任意依赖
    otherwise,error('method must be pdep or dep');
end
thresh=q*(denom/m);
w=find(ps<=thresh);
if isempty(w),crit=0;else,crit=max(ps(w));end
h=p<=crit;crit_p=crit;
%调整后的p值（单调）
adj=zeros(m,1);adj(m)=min(ps(m)*m/m,1);
for i=m-1:-1:1
    adj(i)=min(adj(i+1),ps(i)*m/i);
end
adj_p=zeros(m,1);adj_p(idx)=adj;
end