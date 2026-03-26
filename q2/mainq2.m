%问题2（全局DP）：品类级时间序列+动态定价7日最优补货与定价
%2-1第一问：销售总量—成本加成关系（ln Q对ln(1+m)，含m*与Lerner打印）
%ARMA(p,q)阶数选择（AIC/BIC）、残差检验(Ljung–Box)、ACF/PACF图
%解析解打印：Lerner指数、理论内点价、内点可行性与对照
%成本预测空序列兜底
%7日全局最优价序列（DP），与滚动逐日法逻辑一致
clear;clc;
%用户可调参数
plotLags=30;%ACF/PACF最大滞后
doPlot=true;%是否画图（每个品类2~3张图：时序+残差，诊断，Q-vs-加成）
useBIC=true;%模型选择标准：true=BIC，false=AIC
pqMax=3;%AR/MA最大阶（0..pqMax）
priceBandTighten=0;%价带收紧系数（0=不收紧）
%DP全局解设置
useDP=true;%是否使用7期动态规划求全局最优
priceGridN=75;%价格网格数量（建议50~100）
gridLogScale=false;%价格网格是否用对数刻度
%绘制"第一问：Q vs 加成"关系图
plotMarkupFig=true;
%图像保存配置（默认保存且弹窗）
showFigures=true;%设为false时不弹窗
saveFigures=true;
figDir=fullfile(pwd,'q2_figs');
figFormat='png';figDPI=200;
if saveFigures&&~exist(figDir,'dir'),mkdir(figDir);end
figVis=ternary(showFigures,'on','off');
%读取与标准化列名
fn='q2预处理2-2.xlsx';
T=readtable(fn,'Sheet','Sheet1','PreserveVariableNames',true);
oldNames={'日期','单品编码','单品名称','损耗率（%）','销售单价(元/千克)','批发价格(元/千克)',...
    '利润率','单位成本','成本加成价格','销量（千克）','补货量（千克）','净利润（元）','品类名称'};
newNames={'Date','ItemID','ItemName','LossRate','Price','Wholesale',...
    'ProfitRate','UnitCost','CostPlus','Qty','Replen','NetProfit','Category'};
for k=1:numel(oldNames)
    if any(strcmp(T.Properties.VariableNames,oldNames{k}))
        T=renamevars(T,oldNames{k},newNames{k});
    end
end
if ~ismember('Date',T.Properties.VariableNames)
    cand={'date','DATE'};
    for kk=1:numel(cand)
        if ismember(cand{kk},T.Properties.VariableNames)
            T=renamevars(T,cand{kk},'Date');break;
        end
    end
end
%自适应日期解析
D=T.Date;
if isdatetime(D)
    dt=D;
elseif isnumeric(D)
    v=D(:);v=v(isfinite(v));
    if isempty(v),error('Date列为空或全缺失，无法解析。');end
    if nanmean(v)>7e5,dt=datetime(D,'ConvertFrom','datenum');
    else,dt=datetime(D,'ConvertFrom','excel');end
elseif iscellstr(D)||isstring(D)||ischar(D)
    if ischar(D),D=cellstr(D);end
    fmtList={'yyyy-MM-dd','yyyy/M/d','yyyy/M/dd','yyyy.MM.dd','MM/dd/yyyy','dd/MM/yyyy','yyyyMMdd'};
    dt=NaT(size(D));
    for k=1:numel(fmtList)
        try
            dt_try=datetime(D,'InputFormat',fmtList{k});
            m=isnat(dt)&~isnat(dt_try);dt(m)=dt_try(m);
        catch,end
    end
    m=isnat(dt);if any(m),try dt(m)=datetime(D(m));catch,end,end
else
    error('未识别的Date列类型：%s',class(D));
end
dt.Format='yyyy-MM-dd';
T.Date=dt;
T=T(~isnat(T.Date),:);
%数值列&清洗
numCols={'Qty','Price','Wholesale','LossRate'};
for i=1:numel(numCols)
    c=numCols{i};
    if ~ismember(c,T.Properties.VariableNames),error('缺少必要列：%s',c);end
    if iscellstr(T.(c))||isstring(T.(c))||ischar(T.(c))
        T.(c)=str2double(string(T.(c)));
    else
        T.(c)=double(T.(c));
    end
end
lr=T.LossRate;if nanmedian(lr)>1,lr=lr/100;end
T.LossRate=min(max(lr,0),0.95);
T=T(~isnan(T.Qty)&~isnan(T.Price)&~isnan(T.Wholesale),:);
%聚合品类到日
T.Revenue=T.Qty.*T.Price;
T.Wh_Q=T.Qty.*T.Wholesale;
T.P_Q=T.Qty.*T.Price;
T.Loss_Q=T.Qty.*T.LossRate;
[grp,keyDate,keyCat]=findgroups(T.Date,T.Category);
sum_nonan=@(x)sum(x(~isnan(x)));
QtySum=splitapply(sum_nonan,T.Qty,grp);
RevSum=splitapply(sum_nonan,T.Revenue,grp);
WhQSum=splitapply(sum_nonan,T.Wh_Q,grp);
PQSum=splitapply(sum_nonan,T.P_Q,grp);
LossQSum=splitapply(sum_nonan,T.Loss_Q,grp);
Agg=table(keyDate,keyCat,QtySum,RevSum,WhQSum,PQSum,LossQSum,...
    'VariableNames',{'Date','Category','QtySum','RevSum','WhQSum','PQSum','LossQSum'});
Agg.PriceAvg=Agg.PQSum./max(Agg.QtySum,1e-6);
Agg.WholesaleAvg=Agg.WhQSum./max(Agg.QtySum,1e-6);
Agg.LossAvg=Agg.LossQSum./max(Agg.QtySum,1e-6);
Agg.ProfitReal=Agg.RevSum-(Agg.QtySum./max(1-Agg.LossAvg,1e-4)).*Agg.WholesaleAvg;
Agg=sortrows(Agg,{'Category','Date'});
%时段与特征
trainEnd=datetime(2023,6,30);
predDates=(trainEnd+days(1)):(trainEnd+days(7));
makeFeat=@(dt)struct('dow',weekday(dt),...
    's1',sin(2*pi*day(dt,'dayofyear')/365.25),...
    'c1',cos(2*pi*day(dt,'dayofyear')/365.25));
onehot7=@(dow)full(sparse((1:numel(dow))',dow(:),1,numel(dow),7));
reduce6=@(M)M(:,2:7);
%逐品类拟合、阶数选择、7日定价优化、诊断
Cats=unique(string(Agg.Category));
Cats=Cats(~ismissing(Cats));%过滤missing
resultsDaily=table();resultsSum=table();
allTotal.ReplenTotal=0;allTotal.ProfitTotal=0;
fprintf('\n=================问题2：逐品类7日最优定价与补货（含第一问&解析解&DP）==========\n\n');
for ic=1:numel(Cats)
    cat=Cats(ic);%string
    A=Agg(string(Agg.Category)==cat,:);%string匹配
    Atrain=A(A.Date<=trainEnd,:);
    if height(Atrain)<60
        fprintf('【警告】品类%s样本天数仅%d，结果可能不稳。\n',char(cat),height(Atrain));
    end
    %训练设计矩阵（第二问的regARIMA）
    y=log(max(Atrain.QtySum,1e-6));
    p0=Atrain.PriceAvg;
    p1=[NaN;p0(1:end-1)];
    F=arrayfun(makeFeat,Atrain.Date);
    dow=vertcat(F.dow);
    S=[vertcat(F.s1),vertcat(F.c1)];
    DOW7=onehot7(dow);
    DOW6=reduce6(DOW7);
    X=[log(max(p0,1e-6)),log(max(p1,1e-6)),DOW6,S];
    valid=all(isfinite([y,X]),2);
    y=y(valid);X=X(valid,:);Atrain=Atrain(valid,:);
    %regARIMA阶数选择（p,q in 0..pqMax），按BIC/AIC
    useRegARIMA=exist('regARIMA','file')==2;
    best=struct('mdl',[],'p',0,'q',0,'crit',Inf,'alpha',NaN,'beta',[],'sigma2',NaN,'res',[]);
    if useRegARIMA
        for p=0:pqMax
            for q=0:pqMax
                try
                    M=regARIMA('ARLags',p,'MALags',q,'Intercept',NaN,'Variance',NaN);
                    [mdl,~,logL,~]=estimate(M,y,'X',X,'Display','off');
                    res=infer(mdl,y,'X',X);
                    k=numel(mdl.Beta)+(~isnan(mdl.Intercept))+p+q+1;%含方差
                    n=numel(y);
                    AIC=-2*logL+2*k;BIC=-2*logL+k*log(n);
                    crit=ternary(useBIC,BIC,AIC);
                    if crit<best.crit
                        best=struct('mdl',mdl,'p',p,'q',q,'crit',crit,...
                            'alpha',mdl.Intercept,'beta',mdl.Beta(:)',...
                            'sigma2',var(res),'res',res);
                    end
                catch
                end
            end
        end
    end
    if useRegARIMA&&~isempty(best.mdl)
        alpha=best.alpha;beta=best.beta;sigma2=best.sigma2;res=best.res;
        sel_p=best.p;sel_q=best.q;
        fitMsg=sprintf('regARIMA(%d,%d)选型by%s',sel_p,sel_q,ternary(useBIC,'BIC','AIC'));
    else
        %回退：OLS
        X_OLS=[ones(size(X,1),1),X];b=X_OLS\y;
        alpha=b(1);beta=b(2:end)';e=y-X_OLS*b;sigma2=var(e);res=e;
        sel_p=0;sel_q=0;fitMsg='OLS（无ARMA误差）';
    end
    %Ljung–Box检验
    lbLags=[6,12,18,24];
    [~,Pv]=ljungbox_local(res,lbLags);
    %图1：时序+残差（每个品类都保存）
    if doPlot
        hTS=plot_timeseries(Atrain,res,Pv,char(cat),figVis);
        if saveFigures
            slug=ascii_slug(cat);
            baseTS=fullfile(figDir,sprintf('%02d_%s_ts',ic,slug));
            save_figure(hTS,baseTS,figFormat,figDPI);
        end
        if ~showFigures,close(hTS);end
    end
    %2-1第一问：销售总量—成本加成关系（新增）
    Atrain.cEff=Atrain.WholesaleAvg./max(1-Atrain.LossAvg,1e-4);
    Atrain.mark=max(Atrain.PriceAvg./max(Atrain.cEff,1e-6)-1,1e-6);%m=P/c_eff-1
    yM=log(max(Atrain.QtySum,1e-6));
    X_M=[log(max(Atrain.mark,1e-6)),log(max(Atrain.cEff,1e-6)),DOW6,S];%ln(1+m),ln c_eff,控制
    vM=all(isfinite([yM,X_M]),2);
    alphaM=NaN;betaM=nan(1,size(X_M,2));sig2M=NaN;
    try
        if exist('regARIMA','file')==2
            M1=regARIMA('ARLags',[],'MALags',0,'Intercept',NaN,'Variance',NaN);
            [mdlM,~,~,~]=estimate(M1,yM(vM),'X',X_M(vM,:),'Display','off');
            resM=infer(mdlM,yM(vM),'X',X_M(vM,:));
            alphaM=mdlM.Intercept;betaM=mdlM.Beta(:)';sig2M=var(resM);
        else
            bM=[ones(sum(vM),1),X_M(vM,:)]\yM(vM);
            alphaM=bM(1);betaM=bM(2:end)';resM=yM(vM)-[ones(sum(vM),1),X_M(vM,:)]*bM;sig2M=var(resM);
        end
    catch
        bM=[ones(sum(vM),1),X_M(vM,:)]\yM(vM);
        alphaM=bM(1);betaM=bM(2:end)';resM=yM(vM)-[ones(sum(vM),1),X_M(vM,:)]*bM;sig2M=var(resM);
    end
    b_mark=betaM(1);%ln(1+m)的弹性
    fprintf('——品类：%s\n',char(cat));
    fprintf('模型：%s；弹性β=%.3f（<0期望），滞后价系数γ=%.3f；σ^2=%.4f\n',...
        fitMsg,beta(1),beta(2),sigma2);
    fprintf('Ljung–Box p值：');
    for ii=1:numel(lbLags),fprintf('lag%-2d:%.3f',lbLags(ii),Pv(ii));end
    fprintf('\n价带：p_L=%.2f，p_U=%.2f\n',price_band(Atrain,A,trainEnd,priceBandTighten));
    %解析解相关信息（第二问的价格弹性）
    b_price=beta(1);
    b_priceLag=beta(2);
    b_dow=beta(3:8);
    b_s1=beta(9);
    b_c1=beta(10);
    if b_price<-1
        lerner=-1/b_price;% (P*-c)/P*
        markUpRatio=b_price/(b_price+1);% P*/c_eff
        fprintf(['解析解（单日）表达式：β<-1⇒P*_t=(β/(β+1))·c_{eff,t},',...
            'Lerner=(P*-c)/P*=-1/β。\n']);
        fprintf('本品类：β=%.3f⇒理论Lerner=%.3f，P*/c_eff=%.3f。\n',b_price,lerner,markUpRatio);
    else
        fprintf('解析解（单日）：β=%.3f（|β|≤1），无内点；理论最优价为价带端点之一。\n',b_price);
    end
    %第一问：打印"加成弹性β_m"与最优加成m*、Lerner（结构性）
    if isfinite(b_mark)
        if b_mark<-1
            m_star=-1/(1+b_mark);%m*=-1/(1+β_m)
            lerner_m=-1/b_mark;%Lerner from β_m
            fprintf('【2-1第一问】加成弹性β_m=%.3f；存在理论内点：m*=-1/(1+β_m)=%.3f，Lerner=%.3f；P*/c_eff=1+m*=%.3f。\n',...
                b_mark,m_star,lerner_m,1+m_star);
        else
            fprintf('【2-1第一问】加成弹性β_m=%.3f（|β_m|≤1），无内点；理论最优价为价带端点之一（通常上界）。\n',b_mark);
        end
    else
        fprintf('【2-1第一问】未能稳定识别加成弹性（样本或共线性问题）。\n');
    end
    %"Q vs 加成"关系图
    if doPlot&&plotMarkupFig
        hMK=plot_markup_relation(Atrain,char(cat),figVis);
        if saveFigures
            slug=ascii_slug(cat);
            baseMK=fullfile(figDir,sprintf('%02d_%s_markup',ic,slug));
            save_figure(hMK,baseMK,figFormat,figDPI);
        end
        if ~showFigures,close(hMK);end
    end
    %批发价7步预测（安全兜底）
    Wtrain=Atrain.WholesaleAvg;
    What=forecast_cost_7(Wtrain);
    %损耗率：近30天中位数
    theta=robust_theta(A,trainEnd);
    %价带（单独取一次避免上面打印的匿名值）
    [p_L,p_U]=price_band(Atrain,A,trainEnd,priceBandTighten);
    %预测期特征
    Fp=arrayfun(makeFeat,predDates);
    S_p=[vertcat(Fp.s1),vertcat(Fp.c1)];
    DOW6p=reduce6(onehot7(vertcat(Fp.dow)));
    %价格滞后初值
    if any(A.Date==trainEnd),p_lag0=A.PriceAvg(A.Date==trainEnd);
    else,p_lag0=Atrain.PriceAvg(end);end
    if ~isfinite(p_lag0),p_lag0=median(Atrain.PriceAvg,'omitnan');end
    if ~isfinite(p_lag0),p_lag0=max(p_L,(p_L+p_U)/2);end
    %两种求解：DP全局（默认）/逐日滚动
    tmpCat=table();tmpCat.Category=strings(7,1);tmpCat.Date=predDates';
    tmpCat.PriceStar=nan(7,1);tmpCat.DemandHat=nan(7,1);
    tmpCat.Replen=nan(7,1);tmpCat.Profit=nan(7,1);
    tmpCat.Pint=nan(7,1);tmpCat.Bound=strings(7,1);
    cEffArr=nan(7,1);
    if useDP
        %DP：状态j表示p_{t-1}=Pgrid(j)
        if gridLogScale
            Pgrid=exp(linspace(log(max(p_L,1e-6)),log(p_U),priceGridN))';
        else
            Pgrid=linspace(p_L,p_U,priceGridN)';
        end
        LnPgrid=log(max(Pgrid,1e-9));
        %预计算constPart(t,j)
        constPart=zeros(7,priceGridN);
        for t=1:7
            feat=[DOW6p(t,:),S_p(t,:)]*[b_dow(:);b_s1;b_c1];
            constPart(t,:)=alpha+b_priceLag.*(LnPgrid.')+feat;
        end
        %预计算cEff[t]
        for t=1:7
            cEffArr(t)=What(t)/max(1-theta,1e-4);
        end
        %DP反推：V(t,j)，并设终止V(8,:)=0防越界
        V=zeros(8,priceGridN);
        pol=zeros(7,priceGridN);
        for t=7:-1:1
            for j=1:priceGridN
                bestVal=-Inf;bestA=1;
                cp=constPart(t,j);cEff_t=cEffArr(t);
                for a=1:priceGridN
                    p=Pgrid(a);
                    Dhat=exp(cp+b_price*log(max(p,1e-9)))*exp(0.5*sigma2);
                    Pi=(p-cEff_t)*Dhat;
                    val=Pi+V(t+1,a);
                    if val>bestVal,bestVal=val;bestA=a;end
                end
                V(t,j)=bestVal;pol(t,j)=bestA;
            end
        end
        %初始状态选择
        [~,j0]=min(abs(log(max(p_lag0,1e-9))-LnPgrid));
        j=j0;
        %前向生成最优路径并打印
        for t=1:7
            a=pol(t,j);pStar=Pgrid(a);
            %解析内点
            pInt=NaN;feasibleInt=false;PiInt=NaN;
            if b_price<-1
                pInt=(b_price/(b_price+1))*cEffArr(t);
                feasibleInt=(pInt>=p_L-1e-9)&&(pInt<=p_U+1e-9);
                if feasibleInt
                    Dint=exp(constPart(t,j)+b_price*log(max(pInt,1e-9)))*exp(0.5*sigma2);
                    PiInt=(pInt-cEffArr(t))*Dint;
                end
            end
            %实际日指标
            Dhat=exp(constPart(t,j)+b_price*log(max(pStar,1e-9)))*exp(0.5*sigma2);
            Repl=Dhat/max(1-theta,1e-4);
            Prof=(pStar-cEffArr(t))*Dhat;
            %标注边界
            boundTag="内点";
            if abs(pStar-p_L)<1e-6,boundTag="下界";end
            if abs(pStar-p_U)<1e-6,boundTag="上界";end
            if ~isnan(pInt)&&~feasibleInt,boundTag="内点越界→边界";end
            %记录
            tmpCat.Category(t)=cat;
            tmpCat.PriceStar(t)=pStar;
            tmpCat.DemandHat(t)=Dhat;
            tmpCat.Replen(t)=Repl;
            tmpCat.Profit(t)=Prof;
            tmpCat.Pint(t)=pInt;
            tmpCat.Bound(t)=boundTag;
            %打印
            if ~isnan(pInt)
                if feasibleInt,pintTxt=sprintf('内点=%.2f(可行),Π_int=%.2f',pInt,PiInt);
                else,pintTxt=sprintf('内点=%.2f(越界)',pInt);
                end
            else
                pintTxt='—';
            end
            fprintf('%s|[DP]最优价=%.2f元/kg|预计销量=%.2fkg|补货=%.2fkg|利润=%.2f元|[%s]\n',...
                string(predDates(t)),pStar,Dhat,Repl,Prof,pintTxt);
            j=a;%下一期状态
        end
    else
        %逐日滚动最优
        p_lag=p_lag0;
        for t=1:7
            Wt=What(t);
            cEff=Wt/max(1-theta,1e-4);
            cEffArr(t)=cEff;
            constPart=alpha...
                +b_priceLag*log(max(p_lag,1e-6))...
                +[DOW6p(t,:),S_p(t,:)]*[b_dow(:);b_s1;b_c1];
            demandHat=@(p)exp(constPart+b_price*log(max(p,1e-9)))*exp(0.5*sigma2);
            profitFun=@(p)(p-cEff).*demandHat(p);
            %解析内点
            pInt=NaN;feasibleInt=false;PiInt=NaN;
            if b_price<-1
                pInt=(b_price/(b_price+1))*cEff;
                feasibleInt=(pInt>=p_L-1e-9)&&(pInt<=p_U+1e-9);
                if feasibleInt
                    Dint=demandHat(pInt);
                    PiInt=(pInt-cEff)*Dint;
                end
            end
            %数值优化+端点
            obj=@(p)-profitFun(p);
            pMid=fminbnd(obj,p_L,p_U);
            cand=[p_L,pMid,p_U];
            vals=arrayfun(@(x)-obj(x),cand);
            [~,ii]=max(vals);pStar=cand(ii);
            boundTag="内点";
            if abs(pStar-p_L)<1e-6,boundTag="下界";end
            if abs(pStar-p_U)<1e-6,boundTag="上界";end
            if ~isnan(pInt)&&~feasibleInt,boundTag="内点越界→边界";end
            Dhat=demandHat(pStar);
            Repl=Dhat/max(1-theta,1e-4);
            Prof=profitFun(pStar);
            tmpCat.Category(t)=cat;
            tmpCat.PriceStar(t)=pStar;
            tmpCat.DemandHat(t)=Dhat;
            tmpCat.Replen(t)=Repl;
            tmpCat.Profit(t)=Prof;
            tmpCat.Pint(t)=pInt;
            tmpCat.Bound(t)=boundTag;
            if ~isnan(pInt)
                if feasibleInt,pintTxt=sprintf('内点=%.2f(可行),Π_int=%.2f',pInt,PiInt);
                else,pintTxt=sprintf('内点=%.2f(越界)',pInt);
                end
            else
                pintTxt='—';
            end
            fprintf('%s|最优价=%.2f元/kg|预计销量=%.2fkg|补货=%.2fkg|利润=%.2f元|[%s]\n',...
                string(predDates(t)),pStar,Dhat,Repl,Prof,pintTxt);

            p_lag=pStar;%滚动
        end
    end
    %解析统计：内点可行天数、实际/理论加成对照
    feasibleMask=(~isnan(tmpCat.Pint))&(tmpCat.Pint>=p_L-1e-9)&(tmpCat.Pint<=p_U+1e-9)&(b_price<-1);
    feasibleCnt=sum(feasibleMask);
    meanDiff=mean(abs(tmpCat.PriceStar(feasibleMask)-tmpCat.Pint(feasibleMask)),'omitnan');
    actMarkup=mean((tmpCat.PriceStar-cEffArr)./max(tmpCat.PriceStar,1e-6),'omitnan');
    if b_price<-1
        fprintf('解析内点可行天数=%d/7；可行天均价差|p*-p_int|=%.2f；实际平均加成=%.3f，对应理论加成-1/β=%.3f。\n',...
            feasibleCnt,meanDiff,actMarkup,-1/b_price);
    else
        fprintf('解析结论：β=%.3f（|β|≤1），无内点；实际平均加成=%.3f。\n',b_price,actMarkup);
    end
    %图2：诊断（残差/ACF/PACF）（每个品类都保存）
    if doPlot
        hD=plot_diagnostics(res,plotLags,sprintf('诊断：%s',char(cat)),figVis);
        if saveFigures
            slug=ascii_slug(cat);
            baseDG=fullfile(figDir,sprintf('%02d_%s_diag',ic,slug));
            save_figure(hD,baseDG,figFormat,figDPI);
        end
        if ~showFigures,close(hD);end
    end
    %品类合计
    uniB=unique(cellstr(string(tmpCat.Bound)));
    fprintf('合计(7天)：补货=%.2fkg，利润=%.2f元；其中边界天数=%d/7（%s）。\n\n',...
        nansum(tmpCat.Replen),nansum(tmpCat.Profit),sum(tmpCat.Bound~="内点"),strjoin(uniB,'|'));
    %汇总保存
    resultsDaily=[resultsDaily;tmpCat];
    resultsSum=[resultsSum;table(string(cat),nansum(tmpCat.Replen),nansum(tmpCat.Profit),...
        'VariableNames',{'品类','总进货量（千克）','总净利润'})];
    allTotal.ReplenTotal=allTotal.ReplenTotal+nansum(tmpCat.Replen);
    allTotal.ProfitTotal=allTotal.ProfitTotal+nansum(tmpCat.Profit);
end
%全品类总计
fprintf('=================全品类7天总计==========\n');
fprintf('总补货量=%.2fkg|总净利润=%.2f元\n\n',allTotal.ReplenTotal,allTotal.ProfitTotal);
disp(resultsSum);
%%本脚本用到的本地小函数
function h=plot_timeseries(Atr,res,pvals,cat,figVis)
h=figure('Name',sprintf('时序：%s',cat),'Visible',figVis);
tiledlayout(2,1,'TileSpacing','compact','Padding','compact');
ax1=nexttile;
yyaxis left;plot(Atr.Date,Atr.QtySum,'-');ylabel('销量(kg)');
yyaxis right;plot(Atr.Date,Atr.PriceAvg,'-');ylabel('销售均价(元/kg)');xlabel('时间');
title(sprintf('%s：销量&销售均价',cat));
ax2=nexttile;
plot(Atr.Date,res,'-');yline(0);xlabel('时间');ylabel('残差');
title(sprintf('%s：训练残差（LB p:%.3f/%.3f/%.3f/%.3f）',cat,pvals(1),pvals(2),pvals(3),pvals(4)));
try ax1.Toolbar.Visible='off';ax2.Toolbar.Visible='off';end
end
function h=plot_markup_relation(Atr,cat,figVis)
%Q vs 加成（散点+OLS线）&控制后的偏残差图
h=figure('Name',sprintf('加成关系：%s',cat),'Visible',figVis);
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
%数据
m=max(Atr.mark,1e-6);ce=max(Atr.cEff,1e-6);
y=log(max(Atr.QtySum,1e-6));
x1=log(m+1e-12);%ln(1+m)≈ln m（m>0），用ln(m)近似更稳定；也可换成ln(1+m)
%子图1：散点+简单OLS拟合线
nexttile;
scatter(x1,y,12,'filled');hold on;
Xs=[ones(numel(x1),1),x1];bs=Xs\y;
xx=linspace(min(x1),max(x1),100)';yy=[ones(100,1),xx]*bs;
plot(xx,yy,'LineWidth',1.2);hold off;
xlabel('ln(1+m)');ylabel('ln Q');title(sprintf('%s：Q vs 加成（散点+OLS）',cat));
%子图2：控制ln c_eff、星期、季节后的偏残差
dow=weekday(Atr.Date);
DOW6=full(sparse((1:numel(dow))',dow(:),1,numel(dow),7));DOW6=DOW6(:,2:7);
s1=sin(2*pi*day(Atr.Date,'dayofyear')/365.25);c1=cos(2*pi*day(Atr.Date,'dayofyear')/365.25);
Xc=[log(ce),DOW6,s1,c1];vc=all(isfinite([y,Xc,x1]),2);
bc=[ones(sum(vc),1),Xc(vc,:)]\y(vc);%先回归去除控制项
ry=y(vc)-[ones(sum(vc),1),Xc(vc,:)]*bc;
nexttile;
scatter(x1(vc),ry,12,'filled');hold on;
b2=[ones(sum(vc),1),x1(vc)]\ry;yy2=[ones(100,1),linspace(min(x1(vc)),max(x1(vc)),100)']*b2;
plot(linspace(min(x1(vc)),max(x1(vc)),100),yy2,'LineWidth',1.2);hold off;
xlabel('ln(1+m)');ylabel('偏残差ln Q');title('控制后的偏残差vs ln(1+m)');
try ax=findall(h,'Type','axes');for k=1:numel(ax),ax(k).Toolbar.Visible='off';end,end
end
function r=acf_local(x,m)
x=x(:);x=x-mean(x,'omitnan');n=numel(x);m=min(m,n-1);
if m<=0,r=zeros(0,1);return;end
denom=sum(x.^2,'omitnan');if denom<=0||~isfinite(denom),r=zeros(m,1);return;end
r=zeros(m,1);
for k=1:m
    r(k)=sum(x(1:n-k).*x(1+k:n),'omitnan')/denom;
end
end
function [Q,pvals]=ljungbox_local(res,lagList)
res=res(:);res=res-mean(res,'omitnan');n=numel(res);
lagList=lagList(:).';Q=zeros(1,numel(lagList));pvals=zeros(1,numel(lagList));
if n<2,Q(:)=NaN;pvals(:)=NaN;return;end
maxLag=min(max(lagList),n-1);rho=acf_local(res,maxLag);
for i=1:numel(lagList)
    m=min(lagList(i),n-1);
    if m<=0,Q(i)=NaN;pvals(i)=NaN;continue;end
    k=(1:m)';w=sum((rho(1:m).^2)./(n-k));
    Q(i)=n*(n+2)*w;
    if exist('chi2cdf','file')==2
        pvals(i)=1-chi2cdf(Q(i),m);
    else
        pvals(i)=1-gammainc(Q(i)/2,m/2,'lower');
    end
end
end
function pac=pacf_yw_local(x,m)
x=x(:);x=x-mean(x,'omitnan');n=numel(x);m=min(m,n-1);
if m<=0,pac=zeros(0,1);return;end
pac=zeros(m,1);
for k=1:m
    r=[1;acf_local(x,k)];R=toeplitz(r(1:k));rhs=r(2:k+1);
    a=R\rhs;pac(k)=a(end);
end
end
function h=plot_diagnostics(res,L,ttl,figVis)
res=res(:);
h=figure('Name',ttl,'Visible',figVis);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');
ax1=nexttile;plot(res,'-');yline(0,'k-');title([ttl '残差序列']);xlabel('t');ylabel('res');
r=acf_local(res,L);
ci=1.96/sqrt(max(numel(res),1));
ax2=nexttile;stem(1:numel(r),r,'filled');hold on;yline([ci -ci],'r--');hold off;
title('ACF');xlabel('lag');ylabel('acf');
pac=pacf_yw_local(res,L);
ax3=nexttile;stem(1:numel(pac),pac,'filled');hold on;yline([ci -ci],'r--');hold off;
title('PACF');xlabel('lag');ylabel('pacf');
try ax1.Toolbar.Visible='off';ax2.Toolbar.Visible='off';ax3.Toolbar.Visible='off';end
end
function What=forecast_cost_7(Wtrain)
if isempty(Wtrain)||all(~isfinite(Wtrain)),What=repmat(1.0,7,1);return;end
Wv=Wtrain(isfinite(Wtrain));
if isempty(Wv),What=repmat(1.0,7,1);return;end
if numel(Wv)<10,What=repmat(Wv(end),7,1);return;end
if exist('arima','file')==2
    try
        Mw=arima(1,0,1);
        Mw=estimate(Mw,Wv,'Display','off');
        What=forecast(Mw,7,'Y0',Wv);
        return;
    catch,end
end
if (exist('movmean','file')==2)||(exist('movmean','builtin')==5)
    mm=movmean(Wv,30,'Endpoints','shrink');What=repmat(mm(end),7,1);
else
    m=min(30,numel(Wv));What=repmat(mean(Wv(end-m+1:end),'omitnan'),7,1);
end
end
function theta=robust_theta(A,trainEnd)
recentMask=A.Date>trainEnd-days(30)&A.Date<=trainEnd;
loss_recent=A.LossAvg(recentMask&isfinite(A.LossAvg));
if isempty(loss_recent),loss_recent=A.LossAvg(isfinite(A.LossAvg));end
if isempty(loss_recent),theta=0.10;else,theta=median(loss_recent,'omitnan');end
theta=min(max(theta,0),0.35);
end
function [p_L,p_U]=price_band(Atrain,A,trainEnd,tighten)
recent2=A(A.Date>trainEnd-days(30)&A.Date<=trainEnd,:);
if isempty(recent2),recent2=Atrain(max(1,end-29):end,:);end
p_U=pctile_omitnan(Atrain.PriceAvg,95);
if ~isempty(recent2)&&any(isfinite(recent2.ProfitReal))
    [~,idx]=max(recent2.ProfitReal);p_U=max(p_U,recent2.PriceAvg(idx));
end
p_L=max(pctile_omitnan(Atrain.PriceAvg,10),0.5*median(Atrain.PriceAvg,'omitnan'));
if ~isfinite(p_L),p_L=0.8*p_U;end
if p_L>=p_U,p_L=0.8*p_U;end
if tighten>0,p_U=p_U*(1+tighten);p_L=p_L*(1-tighten);end
end
function v=pctile_omitnan(x,p)
x=x(:);x=x(isfinite(x));
if isempty(x),v=NaN;return;end
try v=prctile(x,p);
catch
    x=sort(x);k=max(1,min(numel(x),round(p/100*numel(x))));v=x(k);
end
end
function save_figure(h,base,fmt,dpi)
%刷新绘制并隐藏坐标区工具栏，避免导出警告与遮挡；文件名唯一（编号+slug）
drawnow;pause(0.01);
ax=findall(h,'Type','axes');
for k=1:numel(ax)
    try ax(k).Toolbar.Visible='off';end
end
fname=[base,'.',lower(fmt)];
try
    exportgraphics(h,fname,'Resolution',dpi);
catch
    switch lower(fmt)
        case 'png',print(h,fname,'-dpng',sprintf('-r%d',dpi));
        case 'jpg',print(h,fname,'-djpeg',sprintf('-r%d',dpi));
        case 'pdf',print(h,fname,'-dpdf');
        otherwise,saveas(h,fname);
    end
end
end
function s=ascii_slug(str)
%返回char
if isstring(str)
    if isscalar(str)&&ismissing(str),s='noname';return;end
    str=char(str);
elseif ~ischar(str)
    str=char(string(str));
end
if isempty(str),s='noname';return;end
out='';
for k=1:numel(str)
    c=str(k);
    if isstrprop(c,'alphanum')||c=='-'||c=='_'
        out=[out,lower(c)];
    elseif c==' '||c=='.'
        out=[out,'_'];
    else
        out=[out,sprintf('u%04X',double(c))];
    end
end
out=regexprep(out,'_+','_');
if isempty(out),out='noname';end
s=out;
end
function z=ternary(c,a,b)
if c
    z=a;
else
    z=b;
end
end