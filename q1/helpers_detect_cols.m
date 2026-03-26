function cols=helpers_detect_cols(varnames)
%根据列名关键字自动识别：日期/时间/名称/数量/类型
%返回字段：date,time,name,qty,type（分别为列名，若没找到则为空）
vn=string(varnames);
%规则库（覆盖常见中文/英文写法）
date_keys=["销售日期","日期","date","Date","交易日期"];
time_keys=["扫码销售时间","时间","time","Time","timestamp","ScanTime"];
name_keys=["蔬菜","品名","名称","商品","skuName","name","Name","品项"];
qty_keys=["销量","数量","千克","kg","KG","Qty","qty","weight","重量"];
type_keys=["销售类型","类型","saleType","Type"];
cols=struct('date','','time','','name','','qty','','type','');
%小工具：按关键字在varnames中找第一个匹配
    function col=pick(keys)
        col='';
        for k=1:numel(keys)
            hit=vn(contains(vn,keys(k),'IgnoreCase',true));
            if ~isempty(hit)
                col=hit(1);
                return;
            end
        end
    end
cols.date=pick(date_keys);
cols.time=pick(time_keys);
cols.name=pick(name_keys);
cols.qty=pick(qty_keys);
cols.type=pick(type_keys);
end