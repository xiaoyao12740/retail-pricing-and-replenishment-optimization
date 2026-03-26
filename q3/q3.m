%问题3：选品+定价+补货（27–33个，订购≥2.5kg，满足品类需求，利润最大）
%列名宽松匹配（含"损耗率(%)"等变体）
%单品需求：ln Q=alpha+beta ln p（稳健：OLS/岭/回退到品类/全局；强制beta<=0）
%两种定价方案并择优（自由最优vs陈列约束价）
%选择优化：intlinprog（若缺工具箱自动贪心）
%五类图：A利润曲线、B lnQ-lnP拟合、C品类目标对比、D敏感性曲线（λ/η/γ）、E结构分布
clear;clc;close all;
set(groot,'defaultAxesToolbarVisible','off');%全局禁用所有坐标区的工具栏
%可调参数
dateStart=datetime(2023,6,24);%历史窗  口
dateEnd=datetime(2023,6,30);
targetDay=datetime(2023,7,1);%目标日（周六）
Kmin=27;Kmax=33;%可售单品数范围
minDisplay=2.5;%最小陈列量（kg）
%需求满足目标（按历史周六均值×γ）
gammaFill=0.95;%目标比例（尽量满足）
lambdaPenalty=8;%未满足每kg的惩罚（元/kg）
etaPenalty=2;%超额每kg的惩罚（元/kg），0表示不惩罚
hardCategoryMeet=false;%若为true，则强制sum D>=Target（硬约束），忽略lambdaPenalty
%单品筛选门槛（可开关）
enforceMinProfit=true;
PiMin=20;%单品利润≥PiMin（元）
enforceMinMargin=true;
marginMin=0.05;%毛利率≥marginMin
%其它建模参数
priceFloorQuant=10;%定价下界：历史10%分位与中位数半数取大
priceCapQuant=95;%定价上界：历史95%分位与历史最大价取大
epsQty=1e-6;%防log(0)
beta_fallback=-0.5;%最末级回退弹性（负）
loss_default=0.10;%若确实无损耗列
ridge_lambda=1e-4;%岭回归正则强度（用于病态/秩亏）
%作图控制
topN_to_plot=12;%单品层A/B两类图，最多绘制的"入选单品"数量（按利润排序）
pgrid_n=200;%A类利润曲线的价格网格密度
fprintf('参数：K=[%d,%d],γ=%.2f,λ=%.1f,η=%.1f,硬满足=%d,利润门槛=%d(%.2f),毛利门槛=%d(%.0f%%)\n',...
    Kmin,Kmax,gammaFill,lambdaPenalty,etaPenalty,hardCategoryMeet,enforceMinProfit,PiMin,enforceMinMargin,100*marginMin);
%读取与宽松重命名
fn='q3预处理.xlsx';
T=readtable(fn,'Sheet','Sheet1','PreserveVariableNames',true);
V=T.Properties.VariableNames;VN=string(V);
norm=lower(strrep(strrep(strrep(VN,'％','%'),'（','('),'）',')'));
norm=regexprep(norm,'\s+','');%去空格
base=regexprep(norm,'\([^)]*\)','');%去括号内容（单位）
findcol=@(cands)find(ismember(base,cands)|contains(base,cands)|...
                     ismember(norm,cands)|contains(norm,cands),1,'first');
%日期
idx=findcol(["日期","date"]);if~isempty(idx),T=renamevars(T,V{idx},'Date');end
%品类
idx=findcol(["品类名称","品类","category"]);if~isempty(idx),T=renamevars(T,V{idx},'Category');end
%单品编码/SKU
idx=findcol(["单品编码","条码","sku","itemid"]);if~isempty(idx),T=renamevars(T,V{idx},'ItemID');end
%单品名称
idx=findcol(["单品名称","品名","名称","itemname"]);if~isempty(idx),T=renamevars(T,V{idx},'ItemName');end
%销量（千克）
idx=findcol(["销量（千克）","销量kg","销量","qty"]);if~isempty(idx),T=renamevars(T,V{idx},'Qty');end
%销售单价
idx=findcol(["销售单价(元/千克)","销售单价","售价","price"]);if~isempty(idx),T=renamevars(T,V{idx},'Price');end
%批发价格/进货价
idx=findcol(["批发价格(元/千克)","批发价格","批发价","进货价","wholesale","cost"]);if~isempty(idx),T=renamevars(T,V{idx},'Wholesale');end
%损耗率
idx=findcol(["损耗率(%)","损耗率（%）","损耗率%","损耗率％","损耗率","损耗","lossrate"]);
if~isempty(idx),T=renamevars(T,V{idx},'LossRate');end
needCols={'Date','Category','ItemID','Qty','Price','Wholesale'};
if~all(ismember(needCols,T.Properties.VariableNames))
    disp('当前表头 ');disp(T.Properties.VariableNames);
    error('缺少关键列（至少应包含Date/Category/ItemID/Qty/Price/Wholesale）。');
end
if~ismember('LossRate',T.Properties.VariableNames)
    warning('未检测到「损耗率」列，按默认%.0f%%处理。',100*loss_default);
    T.LossRate=repmat(loss_default,height(T),1);
end
%日期与数值清洗
D=T.Date;
if~isdatetime(D)
    if isnumeric(D)
        v=D(:);v=v(isfinite(v));if isempty(v),error('Date列为空');end
        if mean(v,'omitnan')>7e5
            T.Date=datetime(D,'ConvertFrom','datenum');
        else
            T.Date=datetime(D,'ConvertFrom','excel');
        end
    else
        if ischar(D),D=cellstr(D);end
        fmts={'yyyy-MM-dd','yyyy/M/d','yyyy.M.d','MM/dd/yyyy','dd/MM/yyyy','yyyyMMdd'};
        dt=NaT(size(D));
        for f=1:numel(fmts)
            try
                dtry=datetime(D,'InputFormat',fmts{f});
                m=isnat(dt)&~isnat(dtry);dt(m)=dtry(m);
            catch
            end
        end
        m=isnat(dt);
        if any(m),try dt(m)=datetime(D(m));catch,end,end
        T.Date=dt;
    end
end
T=T(~isnat(T.Date),:);T.Date.Format='yyyy-MM-dd';
for c=["Qty","Price","Wholesale","LossRate"]
    if iscellstr(T.(c))||isstring(T.(c))||ischar(T.(c))
        T.(c)=str2double(string(T.(c)));
    else
        T.(c)=double(T.(c));
    end
end
if median(T.LossRate,'omitnan')>1,T.LossRate=T.LossRate/100;end
T.LossRate=min(max(T.LossRate,0),0.95);
%历史窗口与品类目标
Thist=T(T.Date>=dateStart&T.Date<=dateEnd,:);
if isempty(Thist),error('历史窗口内无数据');end
Thist.Q=Thist.Qty;Thist.P=Thist.Price;
[grpCD,catG,dateG]=findgroups(Thist.Category,Thist.Date);
dailyCatQty=splitapply(@(x)sum(x,'omitnan'),Thist.Q,grpCD);
CatDaily=table(catG,dateG,dailyCatQty,'VariableNames',{'Category','Date','Qty'});
CatDaily.DOW=weekday(CatDaily.Date);%1=Sun..7=Sat
dowT=weekday(targetDay);
%Map:中文品类到目标需求
catTarget=containers.Map('KeyType','char','ValueType','double');
cats=unique(string(CatDaily.Category));
for ii=1:numel(cats)
    cName=cats(ii);
    Cd=CatDaily(string(CatDaily.Category)==cName,:);
    mu_dow=mean(Cd.Qty(Cd.DOW==dowT),'omitnan');
    if isnan(mu_dow),mu_dow=mean(Cd.Qty,'omitnan');end
    catTarget(char(cName))=max(gammaFill*mu_dow,0);
end
%单品参数估计
items=unique(Thist.ItemID);
nI=numel(items);
Item=struct([]);
%品类级回退beta（Map）
beta_cat=containers.Map('KeyType','char','ValueType','double');
catsAll=unique(Thist.Category);
for k=1:numel(catsAll)
    Rc=Thist(strcmp(Thist.Category,catsAll{k}),:);
    yc=log(max(Rc.Qty,epsQty));xc=log(max(Rc.Price,epsQty));
    v=isfinite(yc)&isfinite(xc);
    if sum(v)>=20&&std(xc(v),'omitnan')>0
        bc=[ones(sum(v),1),xc(v)]\yc(v);
        beta_cat(catsAll{k})=bc(2);
    end
end
%全局回退beta
yg=log(max(Thist.Qty,epsQty));xg=log(max(Thist.Price,epsQty));
w=isfinite(yg)&isfinite(xg);
beta_global=beta_fallback;
if sum(w)>=50&&std(xg(w),'omitnan')>0
    bg=[ones(sum(w),1),xg(w)]\yg(w);
    beta_global=bg(2);
end
getFirstName=@(R)local_get_name(R);

for i=1:nI
    id=items{i};
    R=Thist(strcmp(Thist.ItemID,id),:);
    %名称&品类（稳健）
    name=getFirstName(R);
    if strlength(name)==0,name=string(id);end
    cat=string(R.Category{1});
    %OLS/岭/回退
    y=log(max(R.Qty,epsQty));x=log(max(R.Price,epsQty));
    good=isfinite(y)&isfinite(x);yv=y(good);xv=x(good);
    alpha=NaN;beta=NaN;s2=0.2;
    minN=4;uniqVals=numel(unique(round(xv,3)));
    xr=max(xv)-min(xv);nearConst=(uniqVals<=1)||(xr<1e-3*max(1,abs(median(xv,'omitnan'))));
    if numel(yv)<minN||nearConst
        %回退到品类/全局
        if isKey(beta_cat,char(cat)),beta=beta_cat(char(cat));else,beta=beta_global;end
        alpha=mean(y,'omitnan')-beta*mean(x,'omitnan');
        s2=0.2;
    else
        X=[ones(numel(xv),1),xv];
        if rank(X)<2||cond(X)>1e8
            b=(X'*X+ridge_lambda*eye(2))\(X'*yv);
        else
            b=X\yv;
        end
        alpha=b(1);beta=b(2);
        e=yv-X*b;s2=var(e,'omitnan');s2=min(max(s2,0.02),0.8);
    end
    %经济学约束：beta不得为正
    if~isfinite(beta)||beta>-1e-3
        if isKey(beta_cat,char(cat)),beta=beta_cat(char(cat));else,beta=beta_global;end
        alpha=mean(y,'omitnan')-beta*mean(x,'omitnan');
    end
    %成本/损耗与价界
    wavg=@(a,b)sum(a.*b,'omitnan')/max(sum(b,'omitnan'),1e-6);
    Wholesale=wavg(R.Wholesale,R.Qty);
    Loss=wavg(R.LossRate,R.Qty);Loss=min(max(Loss,0),0.35);
    cEff=Wholesale/max(1-Loss,1e-4);
    p_hist=R.Price(isfinite(R.Price));
    medp=median(p_hist,'omitnan');
    if isempty(p_hist)
        p_floor=max(0.5*Wholesale,0.1);
        p_cap=1.5*p_floor;
    else
        p_floor=max(prctile(p_hist,priceFloorQuant),0.5*medp);
        p_cap=max(prctile(p_hist,priceCapQuant),max(p_hist));
        if~isfinite(p_floor)||p_floor<=0,p_floor=max(0.5*Wholesale,0.1);end
        if~isfinite(p_cap)||p_cap<=p_floor,p_cap=p_floor*1.5;end
    end
    %周几尺度校正（单品优先，其次品类）
    R.DOW=weekday(R.Date);
    mu_i=mean(R.Qty,'omitnan');mu_i_dow=mean(R.Qty(R.DOW==dowT),'omitnan');
    if~isnan(mu_i)&&mu_i>0&&~isnan(mu_i_dow)
        scaleDow=mu_i_dow/mu_i;
    else
        Cd=CatDaily(string(CatDaily.Category)==cat,:);
        mu_c=mean(Cd.Qty,'omitnan');mu_c_dow=mean(Cd.Qty(Cd.DOW==dowT),'omitnan');
        if isnan(mu_c)||mu_c==0||isnan(mu_c_dow),scaleDow=1.0;else,scaleDow=mu_c_dow/max(mu_c,1e-6);end
    end
    A=exp(alpha)*exp(0.5*s2)*scaleDow;%lognormal校正
    Item(i).ItemID=string(id);
    Item(i).ItemName=name;
    Item(i).Category=string(cat);
    Item(i).alpha=alpha;Item(i).beta=beta;Item(i).sigma2=s2;Item(i).A=A;
    Item(i).Wholesale=Wholesale;Item(i).Loss=Loss;Item(i).cEff=cEff;
    Item(i).p_floor=p_floor;Item(i).p_cap=p_cap;
end
%两种定价并择优（订购≥2.5kg）
for i=1:nI
    A=Item(i).A;beta=Item(i).beta;cEff=Item(i).cEff;
    pf=Item(i).p_floor;pc=Item(i).p_cap;
    D=@(p)A*(max(p,1e-6)).^(beta);
    %方案1：自由最优（在边界内）
    profit1=@(p)(p-cEff).*D(p);
    p1_mid=fminbnd(@(p)-profit1(p),pf,pc);
    vals=[-profit1(pf),-profit1(p1_mid),-profit1(pc)];
    [~,arg]=min(vals);
    cand=[pf,p1_mid,pc];p1=cand(arg);
    D1=D(p1);R1=max(D1/(1-Item(i).Loss),minDisplay);Pi1=p1*D1-Item(i).Wholesale*R1;
    %方案2：陈列约束价（销量≈(1-θ)*2.5）
    targetSales=(1-Item(i).Loss)*minDisplay;
    if targetSales>0&&A>0&&beta<-1e-4
        p2=(targetSales/A)^(1/beta);p2=min(max(p2,pf),pc);
    else
        p2=pf;
    end
    D2=D(p2);R2=max(D2/(1-Item(i).Loss),minDisplay);Pi2=p2*D2-Item(i).Wholesale*R2;
    if Pi2>Pi1
        Item(i).p=p2;Item(i).D=D2;Item(i).R=R2;Item(i).Profit=Pi2;Item(i).plan=2;
    else
        Item(i).p=p1;Item(i).D=D1;Item(i).R=R1;Item(i).Profit=Pi1;Item(i).plan=1;
    end
    Item(i).Margin=(Item(i).p-Item(i).cEff)/max(Item(i).p,1e-6);
end
%选择优化（ILP；含最低利润/毛利约束&超额惩罚）
catList=unique(string({Item.Category}));
C=numel(catList);
Tcat=zeros(C,1);
for c=1:C
    key=char(catList(c));
    if isKey(catTarget,key),Tcat(c)=catTarget(key);else,Tcat(c)=0;end
end
Pi=[Item.Profit]';Di=[Item.D]';Ri=[Item.R]';Mg=[Item.Margin]';
catIdx=zeros(nI,1);
for i=1:nI,catIdx(i)=find(catList==Item(i).Category,1);end
%门槛：不达标者禁止入选（ub=0）
allow=true(nI,1);
if enforceMinProfit,allow=allow&(Pi>=PiMin-1e-9);end
if enforceMinMargin,allow=allow&(Mg>=marginMin-1e-9);end
eligible=find(allow);
if numel(eligible)<Kmin
    warning('达门槛的单品数(%d)<Kmin(%d)，自动将Kmin/Kmax调整为%d。',numel(eligible),Kmin,numel(eligible));
    Kmin=numel(eligible);Kmax=numel(eligible);
elseif numel(eligible)<Kmax
    Kmax=numel(eligible);
end
%求解（ILP/贪心）
[zSel,sSlack,oSlack]=solve_selection(Pi,Di,catIdx,Tcat,...
    Kmin,Kmax,allow,lambdaPenalty,etaPenalty,hardCategoryMeet);
%打印结果
selIdx=find(zSel);
fprintf('\n 问题3：%s最优单品清单（共%d个；要求%d–%d）\n',...
    datestr(targetDay,'yyyy-mm-dd'),numel(selIdx),Kmin,Kmax);
TotProfit=0;TotRepl=0;CatSum=zeros(C,1);
for jj=1:numel(selIdx)
    i=selIdx(jj);
    fprintf('[%s]%s|最优价=%.2f元/kg|预计销量=%.2fkg|订购=%.2fkg|利润=%.2f元(方案%d)\n',...
        Item(i).Category,Item(i).ItemName,Item(i).p,Item(i).D,Item(i).R,Item(i).Profit,Item(i).plan);
    TotProfit=TotProfit+Item(i).Profit;
    TotRepl=TotRepl+Item(i).R;
    CatSum(catIdx(i))=CatSum(catIdx(i))+Item(i).D;
end
fprintf('\n品类满足度（目标=周六均值×%.0f%%）\n',100*gammaFill);
for c=1:C
    fprintf('%s:预测销量=%.2fkg|目标=%.2fkg|缺口=%.2fkg|超额=%.2fkg\n',...
        catList{c},CatSum(c),Tcat(c),max(Tcat(c)-CatSum(c),0),max(CatSum(c)-Tcat(c),0));
end
penShort=lambdaPenalty*sum(sSlack)*(~hardCategoryMeet);
penOver=etaPenalty*sum(oSlack);
fprintf('\n总订购量=%.2fkg|总利润=%.2f元|未满足惩罚=%.2f元|超额惩罚=%.2f元\n',...
    TotRepl,TotProfit,penShort,penOver);
%=输出目录准备=
outRoot=fullfile(pwd,'q3_figs');
dirA=ensure_dir(fullfile(outRoot,'A_利润曲线'));
dirB=ensure_dir(fullfile(outRoot,'B_lnQlnP拟合'));
dirC=ensure_dir(fullfile(outRoot,'C_品类目标对比'));
dirD=ensure_dir(fullfile(outRoot,'D_敏感性曲线'));
dirE=ensure_dir(fullfile(outRoot,'E_结构分布'));
%=五类图（A）利润曲线=
%仅对"入选单品"中利润最高的topN_to_plot个绘制
[~,ordProfit]=sort(Pi(selIdx),'descend');
plotIdxA=selIdx(ordProfit(1:min(topN_to_plot,numel(selIdx))));
for k=1:numel(plotIdxA)
    i=plotIdxA(k);
    plot_profit_curve(Item(i),pgrid_n,dirA);
end
%=五类图（B）lnQ-lnP拟合=
%同样挑选A中的那些单品绘制拟合散点与拟合线（显示beta与R2）
for k=1:numel(plotIdxA)
    i=plotIdxA(k);
    plot_lnq_lnp(Thist,Item(i),epsQty,dirB);
end
%=五类图（C）品类目标vs供给=
plot_category_bars(catList,Tcat,CatSum,sSlack,oSlack,dirC);
%=五类图（D）敏感性曲线（λ/η/γ）=
%说明：此处为快速复用优化器的扫描，不重复估计单品参数，仅改变Tcat/惩罚
lambda_grid=0:2:14;%可调整
eta_grid=0:1:6;%可调整
gamma_grid=0.85:0.05:1.05;
%(1)扫lambda
S1=sweep_penalty_lambda(Pi,Di,catIdx,Tcat,Kmin,Kmax,allow,etaPenalty,hardCategoryMeet,lambda_grid);
plot_sensitivity_curve(lambda_grid,[S1.Profit],[S1.Shortfall],[],'λ（未满足惩罚）',dirD,'D1_Profit_Shortfall_vs_lambda.png');
%(2)扫eta
S2=sweep_penalty_eta(Pi,Di,catIdx,Tcat,Kmin,Kmax,allow,lambdaPenalty,hardCategoryMeet,eta_grid);
plot_sensitivity_curve(eta_grid,[S2.Profit],[],[S2.Over],'η（超额惩罚）',dirD,'D2_Profit_Over_vs_eta.png');
%(3)扫gamma（目标缩放）
S3=sweep_gamma(Pi,Di,catIdx,CatDaily,catList,dowT,Kmin,Kmax,allow,lambdaPenalty,etaPenalty,hardCategoryMeet,gamma_grid);
plot_sensitivity_curve(gamma_grid,[S3.Profit],[S3.Shortfall],[S3.Over],'γ（目标缩放）',dirD,'D3_Profit_ShortOver_vs_gamma.png');
%五类图（E）结构分布
%E1:beta分布直方图
figure('Name','E1 beta直方图');
betas=[Item.beta];betas=betas(isfinite(betas));
histogram(betas,20);grid on;xlabel('\beta（价格弹性）');ylabel('频数');title('E1 全部单品\beta分布');
savepng(gcf,fullfile(dirE,'E1_beta_hist.png'));
%E2:最终价vs有效成本（仅入选单品）
figure('Name','E2 价格-有效成本散点');
p_final=arrayfun(@(x)x.p,Item(selIdx));
c_eff=arrayfun(@(x)x.cEff,Item(selIdx));
scatter(c_eff,p_final,36,'filled');hold on;plot([min(c_eff)*0.9,max(c_eff)*1.1],[min(c_eff)*0.9,max(c_eff)*1.1],'--');
grid on;xlabel('c^{eff}（有效成本，元/kg）');ylabel('最终定价p（元/kg）');title('E2 入选单品 最终价vs有效成本');
savepng(gcf,fullfile(dirE,'E2_price_vs_ceff.png'));
%E3:入选单品历史价格箱线图（最多topN_to_plot个）
ids_for_box=plotIdxA;%复用A类选中的
figure('Name','E3 历史价格箱线图');
hold on;
labels=strings(0);
for k=1:numel(ids_for_box)
    i=ids_for_box(k);
    R=Thist(strcmp(Thist.ItemID,Item(i).ItemID),:);
    px=R.Price(isfinite(R.Price));
    if numel(px)>=1
        boxchart(k*ones(size(px)),px,'BoxWidth',0.5);
        labels(end+1)=truncate_str(Item(i).ItemName,16);
    end
end
grid on;xlim([0 numel(ids_for_box)+1]);
xticks(1:numel(ids_for_box));xticklabels(labels);xtickangle(45);
ylabel('历史零售单价（元/kg）');title('E3 入选单品 历史价格箱线图');
savepng(gcf,fullfile(dirE,'E3_hist_price_box.png'));
fprintf('\n全部图像已输出到目录：\n%s\n',outRoot);
%局部/工具函数
function name=local_get_name(R)
%稳健地从表R中拿到第一条ItemName
name="";
if ismember('ItemName',R.Properties.VariableNames)&&~isempty(R.ItemName)
    v=R.ItemName(1);
    if isstring(v)
        name=v(1);
    elseif iscell(v)
        if~isempty(v{1})
            name=string(v{1});
        end
    elseif ischar(v)
        name=string(v);
    else
        try
            name=string(v);
        catch
            name="";
        end
    end
end
end
function dirpath=ensure_dir(dirpath)
if~exist(dirpath,'dir'),mkdir(dirpath);end
end
function savepng(figHandle,outpath)
%兼容：优先exportgraphics，失败则saveas
try
    exportgraphics(figHandle,outpath,'Resolution',200);
catch
    try
        saveas(figHandle,outpath);
    catch ME
        warning('保存图像失败：%s',ME.message);
    end
end
end
function s=truncate_str(s0,n)
s=s0;
if strlength(s0)>n
    s=extractBefore(s0,n)+"...";
end
end
function plot_profit_curve(Item,pgrid_n,outDirA)
%A类图：单品利润曲线，标注自由最优价/陈列约束价/最终采用价
A=Item.A;beta=Item.beta;cEff=Item.cEff;pf=Item.p_floor;pc=Item.p_cap;
D=@(p)A*(max(p,1e-6)).^(beta);
profit=@(p)(p-cEff).*D(p);
%自由最优的解析点（截断前）
if beta<-1e-6
    p_star=(beta/(beta+1))*cEff;
else
    p_star=pf;
end
p_star=min(max(p_star,pf),pc);
%陈列约束价（订购≥2.5kg->可售销量≈(1-θ)*2.5）
targetSales=(1-Item.Loss)*2.5;
if targetSales>0&&A>0&&beta<-1e-4
    p_disp=(targetSales/A)^(1/beta);
else
    p_disp=pf;
end
p_disp=min(max(p_disp,pf),pc);
%网格与曲线
pg=linspace(pf,pc,max(50,pgrid_n));
fig=figure('Name',sprintf('A利润曲线%s',Item.ItemName));
plot(pg,arrayfun(profit,pg),'LineWidth',1.6);hold on;grid on;
yl=ylim;
plot([p_star p_star],yl,'--','LineWidth',1.2);
plot([p_disp p_disp],yl,':','LineWidth',1.2);
plot([Item.p Item.p],yl,'-.','LineWidth',1.6);
xlabel('价格p（元/kg）');ylabel('\Pi(p)（元）');
title(sprintf('A利润曲线：[%s]%s',Item.Category,Item.ItemName));
legend({'\Pi(p)','自由最优p_*','陈列价p_{disp}','最终价p_{final}'},'Location','best');
outname=sprintf('A_profit_%s.png',matlab.lang.makeValidName(char(Item.ItemID)));
savepng(fig,fullfile(outDirA,outname));
end
function plot_lnq_lnp(Thist,Item,epsQty,outDirB)
%B类图：lnQ-lnP拟合散点与拟合线（显示beta与R2）
R=Thist(strcmp(Thist.ItemID,Item.ItemID),:);
x=log(max(R.Price,epsQty));y=log(max(R.Qty,epsQty));
v=isfinite(x)&isfinite(y);
x=x(v);y=y(v);
if numel(x)<2
    warning('单品%s样本不足，跳过B图。',Item.ItemID);
    return;
end
X=[ones(numel(x),1),x];
b=[Item.alpha;Item.beta];%使用最终确定的alpha、beta
yhat=X*b;
SSE=sum((y-yhat).^2);SST=sum((y-mean(y)).^2);
R2=1-SSE/max(SST,epsQty);
fig=figure('Name',sprintf('B lnQ-lnP%s',Item.ItemName));
scatter(x,y,30,'filled');hold on;grid on;
plot(x,yhat,'LineWidth',1.6);
xlabel('ln p');ylabel('ln Q');
title(sprintf('B lnQ-lnP：[%s]%s|\\beta=%.3f,R^2=%.3f',Item.Category,Item.ItemName,Item.beta,R2));
outname=sprintf('B_lnQlnP_%s.png',matlab.lang.makeValidName(char(Item.ItemID)));
savepng(fig,fullfile(outDirB,outname));
end
function plot_category_bars(catList,Tcat,CatSum,sSlack,oSlack,outDirC)
%C类图：品类目标vs供给（条形对比+缺口/超额标注）
[~,ordCat]=sort(Tcat,'descend');%便于阅读
Tc=Tcat(ordCat);Sc=CatSum(ordCat);ss=sSlack(ordCat);oo=oSlack(ordCat);
labs=cellstr(catList(ordCat));
fig=figure('Name','C品类目标对比');
bar([Sc Tc],'grouped');grid on;
legend({'供给合计\Sigma D','目标T'},'Location','best');
xticks(1:numel(labs));xticklabels(labs);xtickangle(35);
ylabel('kg');
title('C品类：目标vs供给（含缺口/超额）');
%在每个品类上方标注缺口或超额
hold on;
for i=1:numel(labs)
    yPos=max(Sc(i),Tc(i));
    if ss(i)>0
        txt=sprintf('缺口%.1f',ss(i));
        text(i-0.15,yPos*1.02,txt,'Color',[0.85 0 0],'FontSize',9);
    elseif oo(i)>0
        txt=sprintf('超额%.1f',oo(i));
        text(i-0.15,yPos*1.02,txt,'Color',[0 0.5 0],'FontSize',9);
    end
end
savepng(fig,fullfile(outDirC,'C_category_target_vs_supply.png'));
end
function [zSel,sSlack,oSlack]=solve_selection(Pi,Di,catIdx,Tcat,Kmin,Kmax,allow,lambdaPenalty,etaPenalty,hardCategoryMeet)
%求解0-1选择问题（主：intlinprog；备：贪心）
nI=numel(Pi);
C=numel(Tcat);
useILP=exist('intlinprog','file')==2;
zSel=false(nI,1);sSlack=zeros(C,1);oSlack=zeros(C,1);
if useILP
    useShortfall=~hardCategoryMeet;
    useOver=etaPenalty>0;
    nVar=nI+(useShortfall*C)+(useOver*C);
    f=zeros(nVar,1);
    f(1:nI)=-Pi;
    if useShortfall,f(nI+1:nI+C)=lambdaPenalty;end
    if useOver,f(nI+(useShortfall*C)+(1:C))=etaPenalty;end
    lb=zeros(nVar,1);ub=ones(nVar,1)*Inf;
    ub(1:nI)=allow;%不达标者ub=0
    intcon=1:nI;
    A=[];b=[];Aeq=[];beq=[];
    %Kmin<=sum z<=Kmax
    row=zeros(1,nVar);row(1,1:nI)=-1;A=[A;row];b=[b;-Kmin];
    row=zeros(1,nVar);row(1,1:nI)=1;A=[A;row];b=[b;Kmax];
    %品类覆盖与超额
    for c=1:C
        idxZ=(catIdx==c);
        if~any(idxZ),continue;end
        %sum D z+s_c>=Tcat->-sum D z-s_c<=-Tcat
        if useShortfall
            row=zeros(1,nVar);
            row(1,find(idxZ))=-Di(idxZ);
            row(1,nI+c)=-1;
            A=[A;row];b=[b;-Tcat(c)];
        else
            row=zeros(1,nVar);
            row(1,find(idxZ))=-Di(idxZ);
            A=[A;row];b=[b;-Tcat(c)];
        end
        %sum D z-o_c<=Tcat
        if useOver
            row2=zeros(1,nVar);
            row2(1,find(idxZ))=Di(idxZ);
            row2(1,nI+(useShortfall*C)+c)=-1;
            A=[A;row2];b=[b;Tcat(c)];
        end
    end
    opts=optimoptions('intlinprog','Display','off');
    [xopt,~,exitflag]=intlinprog(f,intcon,A,b,Aeq,beq,lb,ub,opts);
    if exitflag>0
        zSel=xopt(1:nI)>0.5;
        if~hardCategoryMeet,sSlack=xopt(nI+1:nI+C);end
        if etaPenalty>0,oSlack=xopt(nI+(~hardCategoryMeet*C)+(1:C));end
        return;
    else
        warning('intlinprog未找到整数最优解，回退贪心。');
    end
end
%贪心回退
zSel=false(nI,1);picked=0;
remain=Tcat;%剩余缺口
score=Pi./max(Di,1e-6);%单位销量利润密度
score(~allow)=-inf;
[~,ord]=sort(score,'descend');
for kk=1:numel(ord)
    i=ord(kk);if~isfinite(score(i)),continue;end
    c=catIdx(i);
    if picked<Kmax
        if remain(c)>0||picked<Kmin
            zSel(i)=true;picked=picked+1;remain(c)=max(remain(c)-Di(i),0);
        end
    end
    if picked>=Kmin&&all(remain<=0),break;end
end
%若还不够Kmin，按净收益-超额惩罚继续补
if sum(zSel)<Kmin
    left=find(~zSel&allow);
    adj=Pi(left)-etaPenalty*Di(left);
    [~,o2]=sort(adj,'descend');
    need=Kmin-sum(zSel);
    pick=left(o2(1:min(need,numel(o2))));
    zSel(pick)=true;
end
%若超过Kmax
if sum(zSel)>Kmax
    idx=find(zSel);
    adj2=Pi(idx)-etaPenalty*Di(idx);
    [~,o3]=sort(adj2,'ascend');
    zSel(idx(o3(1:sum(zSel)-Kmax)))=false;
end
%计算s/o
C=numel(Tcat);
supplyCat=accumarray(catIdx(zSel),Di(zSel),[C,1],@sum,0);
sSlack=max(Tcat-supplyCat,0);
oSlack=max(supplyCat-Tcat,0);
end
function plot_sensitivity_curve(xgrid,profitArr,shortArr,overArr,xlab,outDir,fname)
fig=figure('Name',['D敏感性' xlab]);
yyaxis left;
plot(xgrid,profitArr,'-o','LineWidth',1.6);ylabel('总利润（元）');grid on;
yyaxis right;
hold on;
if~isempty(shortArr)
    plot(xgrid,shortArr,'-s','LineWidth',1.6);
end
if~isempty(overArr)
    plot(xgrid,overArr,'-^','LineWidth',1.6);
end
xlabel(xlab);
legendStr={'总利润'};
if~isempty(shortArr),legendStr{end+1}='总缺口（kg）';end
if~isempty(overArr),legendStr{end+1}='总超额（kg）';end
legend(legendStr,'Location','best');
title(['D敏感性：',xlab,'扫描']);
savepng(fig,fullfile(outDir,fname));
end
function S=sweep_penalty_lambda(Pi,Di,catIdx,Tcat,Kmin,Kmax,allow,etaPenalty,hardCategoryMeet,lambda_grid)
S=struct('Profit',[],'Shortfall',[],'Over',[]);
for t=1:numel(lambda_grid)
    lam=lambda_grid(t);
    [zSel,sSlack,oSlack]=solve_selection(Pi,Di,catIdx,Tcat,Kmin,Kmax,allow,lam,etaPenalty,hardCategoryMeet);
    S(t).Profit=sum(Pi(zSel))-lam*sum(sSlack)-etaPenalty*sum(oSlack);
    S(t).Shortfall=sum(sSlack);
    S(t).Over=sum(oSlack);
end
end
function S=sweep_penalty_eta(Pi,Di,catIdx,Tcat,Kmin,Kmax,allow,lambdaPenalty,hardCategoryMeet,eta_grid)
S=struct('Profit',[],'Shortfall',[],'Over',[]);
for t=1:numel(eta_grid)
    et=eta_grid(t);
    [zSel,sSlack,oSlack]=solve_selection(Pi,Di,catIdx,Tcat,Kmin,Kmax,allow,lambdaPenalty,et,hardCategoryMeet);
    S(t).Profit=sum(Pi(zSel))-lambdaPenalty*sum(sSlack)-et*sum(oSlack);
    S(t).Shortfall=sum(sSlack);
    S(t).Over=sum(oSlack);
end
end
function S=sweep_gamma(Pi,Di,catIdx,CatDaily,catList,dowT,Kmin,Kmax,allow,lambdaPenalty,etaPenalty,hardCategoryMeet,gamma_grid)
%仅改变目标Tcat（由gamma控制）；不重新估计单品参数
S=struct('Profit',[],'Shortfall',[],'Over',[]);
%预先计算每品类的周六均值&全周均值
Cnames=string(catList);
mu_sat=zeros(numel(Cnames),1);mu_all=zeros(numel(Cnames),1);hasSat=false(numel(Cnames),1);
for ii=1:numel(Cnames)
    Cd=CatDaily(string(CatDaily.Category)==Cnames(ii),:);
    mu_sat(ii)=mean(Cd.Qty(Cd.DOW==dowT),'omitnan');
    mu_all(ii)=mean(Cd.Qty,'omitnan');
    hasSat(ii)=~isnan(mu_sat(ii));
end
baseT=mu_sat;mask=isnan(baseT);
baseT(mask)=mu_all(mask);
baseT(~isfinite(baseT))=0;
for t=1:numel(gamma_grid)
    gamma=gamma_grid(t);
    Tcat=max(gamma*baseT,0);
    [zSel,sSlack,oSlack]=solve_selection(Pi,Di,catIdx,Tcat,Kmin,Kmax,allow,lambdaPenalty,etaPenalty,hardCategoryMeet);
    S(t).Profit=sum(Pi(zSel))-lambdaPenalty*sum(sSlack)-etaPenalty*sum(oSlack);
    S(t).Shortfall=sum(sSlack);
    S(t).Over=sum(oSlack);
end
end