/**
 * 标签页数据接口
 * 定义编辑器标签页的基本属性
 */
import { ThemeColors, getTheme } from '../utils/ThemeColors';

export interface TabItem {
  /** 标签唯一标识 */
  id: string;
  /** 标签显示标题（文件名） */
  title: string;
  /** 文件是否已修改（未保存） */
  isModified: boolean;
  /** 文件路径（可选） */
  filePath?: string;
  /** 文件图标/语言类型标识 */
  language?: string;
}

/**
 * 编辑器标签栏组件
 *
 * 提供类似 Notepad++ 的多标签页管理能力：
 * - 水平可滚动标签列表
 * - 激活标签高亮显示
 * - 未保存修改指示器（圆点）
 * - 每标签有关闭按钮
 * - 新建标签按钮
 * - 长按/右键上下文菜单支持
 * - 响应式布局适配手机、平板等不同屏幕尺寸
 * - 遵循华为 HarmonyOS 设计指南
 */
@Component
export struct EditorTabBarImpl {
  // ========== 外部数据绑定 ==========

  /** 标签列表（单向绑定，由父组件管理） */
  @Prop tabs: TabItem[] = [];

  /** 当前激活的标签 ID（单向绑定） */
  @Prop @Watch('onActiveTabChange') activeTabId: string = '';

  // ========== 样式配置属性 ==========

  /** 标签最小宽度 (vp) */
  @Prop tabMinWidth: number = 88;
  /** 标签最大宽度 (vp) */
  @Prop tabMaxWidth: number = 200;
  /** 标签高度 (vp) */
  @Prop tabHeight: number = 36;

  // ========== 事件回调 ==========

  /** 点击标签时触发 */
  onTabClick?: (tabId: string) => void;
  /** 关闭标签时触发 */
  onTabClose?: (tabId: string) => void;
  /** 点击新建标签时触发 */
  onNewTab?: () => void;
  /** 长按/右键标签时触发（上下文菜单） */
  onTabContextMenu?: (tabId: string, x: number, y: number) => void;
  /** 标签拖拽排序完成时触发 */
  onTabReorder?: (fromIndex: number, toIndex: number) => void;
  onCloseOthers?: (tabId: string) => void;
  onCloseAll?: () => void;

  // ========== 响应式全局状态 ==========

  /** 当前断点（sm | md | lg | xl），由 AppStorage 全局注入 */
  @StorageProp('currentBreakpoint') currentBreakpoint: string = 'md';
  /** 窗口宽度，由 AppStorage 全局注入 */
  @StorageProp('windowWidth') windowWidth: number = 360;
  @StorageProp('currentColorMode') currentColorMode: string = 'light';

  private col(): ThemeColors {
    return getTheme(this.currentColorMode === 'dark');
  }

  // ========== 内部状态 ==========

  /** 滚动控制器 */
  private scroller: Scroller = new Scroller();
  /** 上下文菜单关联的标签 ID */
  @State contextMenuTabId: string = '';
  // 临时存右键/长按的标签 ID（onClick 时设置）

  // ========== 计算属性（响应式样式） ==========

  /**
   * 根据当前断点和窗口宽度计算响应式标签宽度
   *   sm  (手机竖屏):  紧凑模式，标签较窄
   *   md  (平板竖屏/手机横屏): 适中宽度
   *   lg+ (平板横屏/大屏): 宽松模式
   */
  private getResponsiveTabWidth(): number {
    const tabCount: number = Math.max(this.tabs.length, 1);
    if (this.currentBreakpoint === 'sm') {
      // 手机竖屏：计算可用宽度（窗口 - 新标签按钮 - 箭头 - 边距）
      const availableWidth: number = this.windowWidth - 48 - 16;
      const calcWidth: number = Math.floor(availableWidth / Math.max(1, Math.min(tabCount, 5)));
      return Math.max(this.tabMinWidth, Math.min(calcWidth, 140));
    } else if (this.currentBreakpoint === 'md') {
      const calcWidth: number = Math.floor((this.windowWidth - 80) / Math.min(tabCount, 8));
      return Math.max(this.tabMinWidth, Math.min(calcWidth, 175));
    } else {
      // lg / xl：每个标签最宽
      return Math.max(130, Math.min(this.tabMaxWidth,
        Math.floor((this.windowWidth - 100) / Math.min(tabCount, 12))));
    }
  }

  /**
   * 获取标签背景色（基于系统颜色令牌，支持深色模式）
   */
  private getTabBackground(isActive: boolean): ResourceColor {
    if (isActive) {
      return this.col().tabActiveBg;
    }
    return Color.Transparent;
  }

  private getTabTextColor(isActive: boolean): ResourceColor {
    if (isActive) {
      return this.col().text;
    }
    return this.col().textSecondary;
  }

  // ========== 构建主布局 ==========

  build() {
    Column() {
      // 标签栏主容器
      Row() {
        // 左滚动箭头（仅小屏显示）
        this.LeftArrowBuilder()

        // 可滚动标签区域
        Scroll(this.scroller) {
          Row() {
            ForEach(this.tabs, (tab: TabItem, index: number) => {
              this.TabItemBuilder(tab, index)
            }, (tab: TabItem) => tab.id)

            // 新标签按钮
            this.NewTabButtonBuilder()
          }
          .height(this.tabHeight + 8)
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Start)
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.TopStart)

        // 右滚动箭头（仅小屏显示）
        this.RightArrowBuilder()
      }
      .width('100%')
      .height(this.tabHeight + 8)
      .padding({ top: 0, bottom: 0, left: 0, right: 0 })
      .backgroundColor(this.col().bg)
      .justifyContent(FlexAlign.Start)

      // 标签栏底部细分割线
      Divider()
        .width('100%')
        .height(1)
        .color(this.col().border)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ========== 构建器：单个标签项 ==========

  @Builder
  TabItemBuilder(tab: TabItem, index: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
        // 左侧内边距
        Blank().width(8)

        // 未保存修改指示圆点
        if (tab.isModified) {
          Text('●')
            .fontSize(10)
            .fontColor('#E8A84C')
            .margin({ right: 4 })
        }

        // 标签图标（文件类型）
        this.FileIconBuilder(tab.language)

        // 标签标题文字
        Text(tab.title)
          .fontSize(this.currentBreakpoint === 'sm' ? 12 : 13)
          .fontColor(this.getTabTextColor(tab.id === this.activeTabId))
          .fontWeight(tab.id === this.activeTabId ? FontWeight.Medium : FontWeight.Normal)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
          .margin({ left: 4, right: 4 })

        // 关闭按钮
        this.TabCloseButtonBuilder(tab)

        // 右侧内边距
        Blank().width(4)
      }
      .width(this.getResponsiveTabWidth())
      .height(this.tabHeight)
      .backgroundColor(this.getTabBackground(tab.id === this.activeTabId))
      .borderRadius({
        topLeft: 8,
        topRight: 8,
        bottomLeft: 0,
        bottomRight: 0
      })
      .border({
        width: tab.id === this.activeTabId ? { bottom: 2 } : { bottom: 0 },
        color: tab.id === this.activeTabId ? this.col().tabBorder : Color.Transparent
      })
      .clip(true)
      .animation({ duration: 200, curve: Curve.Smooth })
      .onClick((): void => {
        this.contextMenuTabId = tab.id;
        this.handleTabClick(tab.id);
      })
      .bindContextMenu(this.TabContextBuilder, ResponseType.LongPress, {
        placement: Placement.BottomLeft
      })

      // 悬浮关闭按钮（部分场景下替代内联关闭按钮）
    }
    .margin({ left: 2, right: 2 })
  }

  // ========== 构建器：关闭按钮 ==========

  @Builder
  TabCloseButtonBuilder(tab: TabItem) {
    Text('✕')
      .fontSize(11)
      .fontColor(this.col().textSecondary)
      .width(22)
      .height(22)
      .textAlign(TextAlign.Center)
      .borderRadius(11)
      .backgroundColor(Color.Transparent)
      .opacity(tab.id === this.activeTabId ? 0.7 : 0)
      .hitTestBehavior(tab.id === this.activeTabId ? HitTestMode.Block : HitTestMode.None)
      .onClick((): void => {
        if (this.onTabClose) {
          this.onTabClose(tab.id);
        }
      })
  }

  // ========== 标签右键菜单 ==========

  @Builder
  TabContextBuilder() {
    Menu() {
      MenuItem({ content: '关闭' })
        .onClick((): void => {
          if (this.onTabClose) {
            const id = this.contextMenuTabId ? this.contextMenuTabId : this.activeTabId;
            this.onTabClose(id);
          }
        })
      MenuItem({ content: '关闭其他' })
        .onClick((): void => {
          if (this.onCloseOthers) {
            const id = this.contextMenuTabId ? this.contextMenuTabId : this.activeTabId;
            this.onCloseOthers(id);
          }
        })
      MenuItem({ content: '关闭所有' })
        .onClick((): void => {
          if (this.onCloseAll) {
            this.onCloseAll();
          }
        })
    }
  }

  // ========== 构建器：文件类型图标 ==========

  @Builder
  FileIconBuilder(language?: string) {
    if (language === 'ets' || language === 'ts' || language === 'arkts') {
      Text('TS')
        .fontSize(9)
        .fontColor('#3178C6')
        .width(16)
        .height(16)
        .textAlign(TextAlign.Center)
        .backgroundColor('#3178C620')
        .borderRadius(3)
        .margin({ right: 4 })
    } else if (language === 'js') {
      Text('JS')
        .fontSize(9)
        .fontColor('#F7DF1E')
        .width(16)
        .height(16)
        .textAlign(TextAlign.Center)
        .backgroundColor('#F7DF1E20')
        .borderRadius(3)
        .margin({ right: 4 })
    } else if (language === 'html') {
      Text('🌐')
        .fontSize(10)
        .margin({ right: 4 })
    } else if (language === 'json') {
      Text('{}')
        .fontSize(9)
        .fontColor(this.col().textSecondary)
        .margin({ right: 4 })
    } else if (language === 'markdown' || language === 'md') {
      Text('MD')
        .fontSize(9)
        .fontColor('#083FA0')
        .width(16)
        .height(16)
        .textAlign(TextAlign.Center)
        .backgroundColor('#083FA020')
        .borderRadius(3)
        .margin({ right: 4 })
    } else {
      // 默认文件图标（空白文档）
      Text('📄')
        .fontSize(10)
        .margin({ right: 4 })
    }
  }

  // ========== 构建器：新建标签按钮 ==========

  @Builder
  NewTabButtonBuilder() {
    Row() {
      Text('+')
        .fontSize(20)
        .fontColor(this.col().textSecondary)
        .fontWeight(FontWeight.Lighter)
        .textAlign(TextAlign.Center)
    }
    .width(32)
    .height(this.tabHeight)
    .justifyContent(FlexAlign.Center)
    .borderRadius(8)
    .backgroundColor(this.col().surface)
    .margin({ left: 4, right: 8 })
    .opacity(0.7)
    .onClick((): void => {
      if (this.onNewTab) {
        this.onNewTab();
      }
    })
  }

  // ========== 构建器：左滚动箭头 ==========

  @Builder
  LeftArrowBuilder() {
    Text('◀')
      .fontSize(12)
      .fontColor(this.col().textSecondary)
      .width(20)
      .height(20)
      .textAlign(TextAlign.Center)
      .margin({ left: 4, right: 2 })
      .visibility(this.currentBreakpoint === 'sm' ? Visibility.Visible : Visibility.None)
      .onClick((): void => {
        const offset = this.scroller.currentOffset();
        const xOffset: number = offset !== undefined ? offset.xOffset : 0;
        this.scroller.scrollTo({
          xOffset: Math.max(0, xOffset - this.getResponsiveTabWidth() * 2),
          yOffset: 0,
          animation: { duration: 200, curve: Curve.EaseOut }
        });
      })
  }

  // ========== 构建器：右滚动箭头 ==========

  @Builder
  RightArrowBuilder() {
    Text('▶')
      .fontSize(12)
      .fontColor(this.col().textSecondary)
      .width(20)
      .height(20)
      .textAlign(TextAlign.Center)
      .margin({ left: 2, right: 4 })
      .visibility(this.currentBreakpoint === 'sm' ? Visibility.Visible : Visibility.None)
      .onClick((): void => {
        const offset2 = this.scroller.currentOffset();
        const xOffset2: number = offset2 !== undefined ? offset2.xOffset : 0;
        this.scroller.scrollTo({
          xOffset: xOffset2 + this.getResponsiveTabWidth() * 2,
          yOffset: 0,
          animation: { duration: 200, curve: Curve.EaseOut }
        });
      })
  }

  // ========== 内部方法 ==========

  /**
   * 处理标签点击：切换激活标签并回调
   */
  private handleTabClick(tabId: string): void {
    if (this.onTabClick) {
      this.onTabClick(tabId);
    }
  }

  /**
   * 滚动到指定标签使其可见
   * @param tabId 目标标签 ID
   */
  scrollToTab(tabId: string): void {
    const index: number = this.tabs.findIndex((t: TabItem) => t.id === tabId);
    if (index < 0) {
      return;
    }
    const tabWidth: number = this.getResponsiveTabWidth();
    const targetX: number = index * (tabWidth + 4); // +4 为 margin
    this.scroller.scrollTo({
      xOffset: Math.max(0, targetX - (this.windowWidth / 4)),
      yOffset: 0,
      animation: { duration: 300, curve: Curve.EaseInOut }
    });
  }

  // ========== 组件即将出现时 ==========

  aboutToAppear(): void {
    // 组件初始化逻辑（如有需要在此添加）
  }

  // ========== 组件销毁时 ==========

  aboutToDisappear(): void {
    // 清理资源（如有需要在此添加）
  }

  // ========== 监听器 ==========

  onActiveTabChange(): void {
    this.scrollToTab(this.activeTabId);
  }
}