%数据提取和整理
data={
'西峡香菇 (1)',4324;
'净藕 (1)',4138;
'西兰花 ',2422;
'云南生菜 (份)',2057;
'云南油麦菜 (份)',2045;
'云南生菜 ',1685;
'枝江青梗散花 ',1592;
'杏鲍菇 (2)',1554;
'菠菜 (份)',1408;
'芜湖青椒 (1)',1299;
'金针菇 (盒)',1183;
'螺丝椒 (份)',1147;
'奶白菜 (份)',1019;
'紫茄子 (2)',1001;
'小米椒 (份)',943;
'上海青 (份)',894;
'双孢菇 (盒)',844;
'云南油麦菜 ',700;
'青梗散花 ',632;
'娃娃菜 ',630
};
%分离品类和数量
categories=data (:,1);
values=cell2mat (data (:,2));
%创建条形图
figure ('Position',[100,100,1400,700])
bar (values)
set (gca,'XTick',1:length (categories),'XTickLabel',categories)
xtickangle (45)
ylabel ('数量 ')
title ('蔬菜品类数量统计 ')
%添加数值标签
text(1:length (values),values,num2str (values),...
'HorizontalAlignment','center',...
'VerticalAlignment','bottom',...
'FontSize',8)
%调整布局
set (gcf,'Color','w')
set (gca,'FontSize',9)
grid on
%设置 Y 轴格式，避免科学计数法
ytickformat ('%.0f')