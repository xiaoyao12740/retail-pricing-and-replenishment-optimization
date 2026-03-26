%数据提取和整理 data={ '芜湖青椒(1)',9026.801; '净藕(1)',7973.447; '西兰花',6832.485; '大白菜',5934.341; '金针菇(盒)',4772; '小米椒(份)',4164; '紫茄子(2)',4017.65; '云南生菜(份)',3710; '枝江红菜苔',3586.793; '洪湖莲藕(粉藕)',3261 };
%分离品类和数值
categories=data (:,1);
values=cell2mat (data (:,2));
%创建条形图
figure ('Position',[100,100,1000,600])
bar (values)
set (gca,'XTick',1:length (categories),'XTickLabel',categories)
xtickangle (45)
ylabel (' 数值 ')
title (' 蔬菜品类数值统计 ')
%添加数值标签
text (1:length (values),values,num2str (values,'%.3f'),...
'HorizontalAlignment','center',...
'VerticalAlignment','bottom',...
'FontSize',9)
%调整布局
set (gcf,'Color','w')
set (gca,'FontSize',10)
grid on
%设置Y轴格式，避免科学计数法
ytickformat ('%.0f')