function veg_daily_stats(xlsxFile,sheet)
%读取"预处理1-1"Excel，剔除空行/退货，计算"每种蔬菜"的日统计并导出表格
if nargin<1||isempty(xlsxFile),xlsxFile='q1预处理1-1.xlsx';end
if nargin<2||isempty(sheet),sheet=1;end
outdir=fullfile(pwd,'out_stats');
if ~exist(outdir,'dir'),mkdir(outdir);end
%读表（保留原始列名）
opts=detectImportOptions(xlsxFile,'Sheet',sheet,'VariableNamingRule','preserve');
T=readtable(xlsxFile,opts);
%剔除整行全空（年分隔空行等）
rowAllMissing=all(ismissing(T),2);
T(rowAllMissing,:)=[];
%自动识别关键列（日期/时间/名称/数量/销售类型）
cols=helpers_detect_cols(T.Properties.VariableNames);
cDate=cols.date;
cTime=cols.time;
cName=cols.name;
cQty=cols.qty;
cType=cols.type;
if isempty(cName)||isempty(cQty)
    error('未识别到"蔬菜名称/品名/商品名称"等，以及"销量/数量/千克/qty"等字段，请检查表头。');
end
%取必要列并规范化
name=string(T{:,cName});
qty=T{:,cQty};
if ~isnumeric(qty),qty=double(qty);end
%日期（优先从"销售日期/日期/date"取；若无，再尝试从"扫码销售时间"推日期）
if ~isempty(cDate)
    dt_raw=T{:,cDate};
    if ~isdatetime(dt_raw)
        try
            dt=datetime(dt_raw);
        catch
            dt=datetime(string(dt_raw),'InputFormat','yyyy-MM-dd');
        end
    else
        dt=dt_raw;
    end
else
    dt=NaT(height(T),1);
end
%如果有扫码时间，补齐日期中的时间（可有可无）
if ~isempty(cTime)
    tm_raw=T{:,cTime};
    try
        tm=timeofday(datetime(string(tm_raw),'InputFormat','HH:mm:ss.SSS'));
    catch
        try
            tm=timeofday(datetime(string(tm_raw),'InputFormat','HH:mm:ss'));
        catch
            tm=duration(zeros(height(T),1),0,0);
        end
    end
    %若日期为空且有时间戳，尝试用time的日期部分（通常不含日期，保守不动）
else
    tm=duration(zeros(height(T),1),0,0);
end
%统一成"日"粒度
if ~all(isnat(dt))
    timestamp=dt+tm;
    day=dateshift(timestamp,'start','day');
else
    error('未识别到日期列（如"销售日期/日期/date"），无法计算"以天为单位"的统计。');
end
%剔除空值与退货记录
%空：名称缺失或数量缺失
mask_valid=~(name==""|ismissing(name)|isnan(qty));
name=name(mask_valid);qty=qty(mask_valid);day=day(mask_valid);
%退货：销量<0或销售类型列包含"退货"
isReturn=false(size(qty));
if ~isempty(cType)
    typ=string(T{:,cType});typ=typ(mask_valid);
    isReturn=isReturn|contains(typ,"退货");
end
isReturn=isReturn|(qty<0);
keep=~isReturn;
name=name(keep);qty=qty(keep);day=day(keep);
%先聚合到"某蔬菜-某天"的日销量（若一天内多条交易，先求和）
G=findgroups(name,day);
daily_qty=splitapply(@(x)sum(x,'omitnan'),qty,G);
[name_u,day_u]=splitapply(@unique,name,G);%#ok<ASGLU>
%重新拿unique键
[veg_list,~,gVeg]=unique(name_u);
%对每个蔬菜的"按日序列"计算统计量
N=numel(veg_list);
total_qty=zeros(N,1);
day_max=zeros(N,1);
day_min=zeros(N,1);
day_mean=zeros(N,1);
day_median=zeros(N,1);
day_skew=zeros(N,1);
day_kurt=zeros(N,1);
day_std=zeros(N,1);
for i=1:N
    x=daily_qty(gVeg==i);%该蔬菜的所有"日销量"
    xv=x(~isnan(x));%去掉NaN
    if isempty(xv)
        total_qty(i)=0;
        day_max(i)=NaN;
        day_min(i)=NaN;
        day_mean(i)=NaN;
        day_median(i)=NaN;
        day_skew(i)=NaN;
        day_kurt(i)=NaN;
        day_std(i)=NaN;
    else
        total_qty(i)=sum(xv);
        day_max(i)=max(xv);
        day_min(i)=min(xv);
        day_mean(i)=mean(xv);
        day_median(i)=median(xv);
        day_skew(i)=skewness(xv,0);%偏度（无偏版本）
        day_kurt(i)=kurtosis(xv,0);%峰度（正态≈3）
        day_std(i)=std(xv,0);
    end
end
%输出表（ASCII列名，避免中文变量名在MATLAB内部报错）
Tout=table(veg_list,total_qty,day_max,day_min,day_mean,day_median,day_skew,day_kurt,day_std,...
    'VariableNames',{'vegetable','total_qty','day_max','day_min','day_mean','day_median','day_skewness','day_kurtosis','day_std'});
%按总量降序
Tout=sortrows(Tout,'total_qty','descend');
%保存
outcsv=fullfile(outdir,'veg_daily_stats.csv');
writetable(Tout,outcsv);
fprintf('已生成：%s\n',outcsv);
end