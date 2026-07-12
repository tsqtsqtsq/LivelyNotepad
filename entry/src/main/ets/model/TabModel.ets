/**
 * 标签页数据模型 - 表示编辑器中的一个打开的文件标签
 */
@Observed
export class TabModel {
  /** 唯一标识符 */
  id: string;
  /** 标签显示名称（文件名） */
  label: string;
  /** 文件完整路径 */
  filePath: string;
  /** 文档文本内容 */
  content: string;
  /** 是否有未保存的修改 */
  isModified: boolean;
  /** 是否为当前活动标签 */
  isActive: boolean;
  /** 文件编码格式 */
  encoding: string;
  /** 换行符类型 */
  lineEnding: LineEndingType;
  /** 光标行位置（0-based） */
  cursorLine: number;
  /** 光标列位置（0-based） */
  cursorColumn: number;
  /** 垂直滚动偏移 */
  scrollTop: number;
  /** 水平滚动偏移 */
  scrollLeft: number;
  /** 编程语言类型（用于语法高亮） */
  language: ProgrammingLanguage;
  /** 文件最后保存时间戳 */
  lastSavedTime: number;
  /** 文件大小（字节） */
  fileSize: number;

  constructor(
    id: string,
    label: string,
    filePath: string,
    content: string = '',
    language: ProgrammingLanguage = ProgrammingLanguage.PLAIN_TEXT
  ) {
    this.id = id;
    this.label = label;
    this.filePath = filePath;
    this.content = content;
    this.isModified = false;
    this.isActive = false;
    this.encoding = 'UTF-8';
    this.lineEnding = LineEndingType.LF;
    this.cursorLine = 0;
    this.cursorColumn = 0;
    this.scrollTop = 0;
    this.scrollLeft = 0;
    this.language = language;
    this.lastSavedTime = Date.now();
    this.fileSize = 0;
  }

  /**
   * 更新光标位置
   */
  setCursor(line: number, column: number): void {
    this.cursorLine = line;
    this.cursorColumn = column;
  }

  /**
   * 更新滚动位置
   */
  setScroll(top: number, left: number): void {
    this.scrollTop = top;
    this.scrollLeft = left;
  }

  /**
   * 标记为已修改
   */
  markModified(): void {
    this.isModified = true;
  }

  /**
   * 标记为已保存
   */
  markSaved(): void {
    this.isModified = false;
    this.lastSavedTime = Date.now();
  }

  /**
   * 获取行数
   */
  getLineCount(): number {
    if (!this.content || this.content.length === 0) {
      return 1;
    }
    let count = 1;
    for (let i = 0; i < this.content.length; i++) {
      if (this.content.charAt(i) === '\n') count++;
    }
    return count;
  }

  getLine(lineIndex: number): string {
    const lines = this.content.split('\n');
    if (lineIndex >= 0 && lineIndex < lines.length) {
      return lines[lineIndex];
    }
    return '';
  }

  /**
   * 克隆标签页数据
   */
  clone(): TabModel {
    const cloned = new TabModel(this.id, this.label, this.filePath, this.content, this.language);
    cloned.isModified = this.isModified;
    cloned.isActive = this.isActive;
    cloned.encoding = this.encoding;
    cloned.lineEnding = this.lineEnding;
    cloned.cursorLine = this.cursorLine;
    cloned.cursorColumn = this.cursorColumn;
    cloned.scrollTop = this.scrollTop;
    cloned.scrollLeft = this.scrollLeft;
    cloned.lastSavedTime = this.lastSavedTime;
    cloned.fileSize = this.fileSize;
    return cloned;
  }
}

/**
 * 换行符类型枚举
 */
export enum LineEndingType {
  /** Unix/Linux 换行符 \n */
  LF = 'LF',
  /** Windows 换行符 \r\n */
  CRLF = 'CRLF',
  /** 旧 Mac 换行符 \r */
  CR = 'CR'
}

/**
 * 支持的编程语言类型（用于语法高亮）
 */
export enum ProgrammingLanguage {
  PLAIN_TEXT = 'plaintext',
  JAVASCRIPT = 'javascript',
  TYPESCRIPT = 'typescript',
  ARKTS = 'arkts',
  HTML = 'html',
  CSS = 'css',
  JSON = 'json',
  XML = 'xml',
  MARKDOWN = 'markdown',
  PYTHON = 'python',
  JAVA = 'java',
  KOTLIN = 'kotlin',
  C = 'c',
  CPP = 'cpp',
  CSHARP = 'csharp',
  GO = 'go',
  RUST = 'rust',
  SWIFT = 'swift',
  SQL = 'sql',
  SHELL = 'shell',
  YAML = 'yaml',
  TOML = 'toml'
}

/**
 * 根据文件扩展名推断语言类型
 */
export function getLanguageFromExtension(fileName: string): ProgrammingLanguage {
  const dotIdx = fileName.lastIndexOf('.');
  const ext = dotIdx >= 0 ? fileName.substring(dotIdx).toLowerCase() : '';
  switch (ext) {
    case '.js':
    case '.mjs':
      return ProgrammingLanguage.JAVASCRIPT;
    case '.ts':
      return ProgrammingLanguage.TYPESCRIPT;
    case '.ets':
      return ProgrammingLanguage.ARKTS;
    case '.html':
    case '.htm':
      return ProgrammingLanguage.HTML;
    case '.css':
      return ProgrammingLanguage.CSS;
    case '.json':
    case '.json5':
      return ProgrammingLanguage.JSON;
    case '.xml':
    case '.svg':
      return ProgrammingLanguage.XML;
    case '.md':
    case '.markdown':
      return ProgrammingLanguage.MARKDOWN;
    case '.py':
      return ProgrammingLanguage.PYTHON;
    case '.java':
      return ProgrammingLanguage.JAVA;
    case '.kt':
    case '.kts':
      return ProgrammingLanguage.KOTLIN;
    case '.c':
    case '.h':
      return ProgrammingLanguage.C;
    case '.cpp':
    case '.cc':
    case '.cxx':
    case '.hpp':
    case '.hxx':
      return ProgrammingLanguage.CPP;
    case '.cs':
      return ProgrammingLanguage.CSHARP;
    case '.go':
      return ProgrammingLanguage.GO;
    case '.rs':
      return ProgrammingLanguage.RUST;
    case '.swift':
      return ProgrammingLanguage.SWIFT;
    case '.sql':
      return ProgrammingLanguage.SQL;
    case '.sh':
    case '.bash':
    case '.zsh':
      return ProgrammingLanguage.SHELL;
    case '.yaml':
    case '.yml':
      return ProgrammingLanguage.YAML;
    case '.toml':
      return ProgrammingLanguage.TOML;
    default:
      return ProgrammingLanguage.PLAIN_TEXT;
  }
}

/**
 * 标签页状态管理类 - 管理编辑器所有打开的标签页
 */
@Observed
export class TabStateManager {
  /** 所有打开的标签页列表 */
  tabs: TabModel[];
  /** 当前活动标签页的ID */
  activeTabId: string;
  /** 标签页ID计数器 */
  private idCounter: number;
  /** 标签页变更监听器列表 */
  private listeners: TabStateChangeListener[];
  /** 撤销历史（每个标签页的编辑快照） */
  private undoStacks: Map<string, string[]> = new Map();
  /** 重做历史 */
  private redoStacks: Map<string, string[]> = new Map();
  /** 最大历史记录数 */
  private readonly maxHistory: number = 50;
  private tabMap: Map<string, TabModel>;

  /** 触发 tabs 数组的响应式更新（@Observed 不追踪数组内部变异） */
  private triggerTabsChange(): void {
    this.tabs = [...this.tabs];
  }

  constructor() {
    this.tabs = [];
    this.activeTabId = '';
    this.idCounter = 0;
    this.listeners = [];
    this.undoStacks = new Map();
    this.redoStacks = new Map();
    this.tabMap = new Map();
  }

  /**
   * 在内容变更前记录快照（用于撤销）
   */
  pushUndo(tabId: string, content: string): void {
    if (!this.undoStacks.has(tabId)) {
      this.undoStacks.set(tabId, []);
    }
    const stack = this.undoStacks.get(tabId);
    if (!stack) return;
    if (stack.length === 0 || stack[stack.length - 1] !== content) {
      stack.push(content);
      if (stack.length > this.maxHistory) {
        stack.shift();
      }
      this.redoStacks.set(tabId, []);
    }
  }

  undo(tabId: string): string | null {
    const stack = this.undoStacks.get(tabId);
    if (!stack || stack.length < 1) return null;
    const currentContent = this.tabMap.get(tabId)?.content;
    if (currentContent === undefined) return null;
    if (!this.redoStacks.has(tabId)) this.redoStacks.set(tabId, []);
    const redoStack = this.redoStacks.get(tabId);
    if (redoStack) redoStack.push(currentContent);
    const previous = stack.pop();
    return previous !== undefined ? previous : null;
  }

  redo(tabId: string): string | null {
    const redoStack = this.redoStacks.get(tabId);
    if (!redoStack || redoStack.length === 0) return null;
    const currentContent = this.tabMap.get(tabId)?.content;
    if (currentContent === undefined) return null;
    if (!this.undoStacks.has(tabId)) this.undoStacks.set(tabId, []);
    const undoStack = this.undoStacks.get(tabId);
    if (undoStack) undoStack.push(currentContent);
    const next = redoStack.pop();
    return next !== undefined ? next : null;
  }

  /** 关闭标签时清理历史 */
  clearHistory(tabId: string): void {
    this.undoStacks.delete(tabId);
    this.redoStacks.delete(tabId);
  }

  /**
   * 生成唯一标签ID
   */
  private generateTabId(): string {
    this.idCounter++;
    return 'tab_' + this.idCounter + '_' + Date.now();
  }

  /**
   * 创建新标签页
   */
  createNewTab(label: string = '新建文件', filePath: string = '', content: string = ''): TabModel {
    const id = this.generateTabId();
    const language = filePath
      ? getLanguageFromExtension(filePath)
      : ProgrammingLanguage.PLAIN_TEXT;
    const tab = new TabModel(id, label, filePath, content, language);
    this.tabs.push(tab);
    this.tabMap.set(tab.id, tab);
    this.triggerTabsChange();
    this.setActiveTab(id);
    this.notifyListeners(TabStateEventType.TAB_OPENED, tab);
    return tab;
  }

  /**
   * 打开文件作为新标签页
   */
  openFile(label: string, filePath: string, content: string): TabModel {
    const existingTab = this.tabs.find((t: TabModel) => t.filePath === filePath);
    if (existingTab) {
      this.setActiveTab(existingTab.id);
      return existingTab;
    }

    const id = this.generateTabId();
    const language = getLanguageFromExtension(filePath);
    const tab = new TabModel(id, label, filePath, content, language);
    tab.fileSize = content.length;
    this.tabs.push(tab);
    this.tabMap.set(tab.id, tab);
    this.triggerTabsChange();
    this.setActiveTab(id);
    this.notifyListeners(TabStateEventType.TAB_OPENED, tab);
    return tab;
  }

  /**
   * 关闭标签页
   */
  closeTab(tabId: string): boolean {
    const index = this.tabs.findIndex((t: TabModel) => t.id === tabId);
    if (index === -1) {
      return false;
    }

    const closedTab = this.tabs[index];
    this.tabs.splice(index, 1);
    this.tabMap.delete(tabId);
    this.triggerTabsChange();

    this.clearHistory(tabId);
    if (this.activeTabId === tabId) {
      if (this.tabs.length > 0) {
        const newActiveIndex = Math.min(index, this.tabs.length - 1);
        this.activeTabId = this.tabs[newActiveIndex].id;
        this.tabs[newActiveIndex].isActive = true;
      } else {
        this.activeTabId = '';
      }
    }

    this.notifyListeners(TabStateEventType.TAB_CLOSED, closedTab);
    return true;
  }

  /**
   * 设置活动标签页
   */
  setActiveTab(tabId: string): void {
    const currentActive = this.getActiveTab();
    if (currentActive) {
      currentActive.isActive = false;
    }

    const tab = this.tabMap.get(tabId);
    if (tab) {
      tab.isActive = true;
      this.activeTabId = tabId;
      this.notifyListeners(TabStateEventType.TAB_SWITCHED, tab);
    }
  }

  /**
   * 获取活动标签页
   */
  getActiveTab(): TabModel | undefined {
    return this.tabMap.get(this.activeTabId);
  }

  getTabById(tabId: string): TabModel | undefined {
    return this.tabMap.get(tabId);
  }

  /**
   * 获取标签页总数
   */
  getTabCount(): number {
    return this.tabs.length;
  }

  /**
   * 获取所有标签页
   */
  getAllTabs(): TabModel[] {
    return [...this.tabs];
  }

  /**
   * 重建 tabMap（在绕过 createNewTab/openFile 直接操作 tabs 数组后调用）
   */
  rebuildTabMap(): void {
    this.tabMap = new Map();
    for (let i = 0; i < this.tabs.length; i++) {
      this.tabMap.set(this.tabs[i].id, this.tabs[i]);
    }
  }

  /**
   * 更新标签页内容
   */
  updateTabContent(tabId: string, content: string): void {
    const tab = this.tabMap.get(tabId);
    if (tab) {
      tab.content = content;
      tab.markModified();
      this.notifyListeners(TabStateEventType.CONTENT_CHANGED, tab);
      this.triggerTabsChange();
    }
  }

  /**
   * 保存标签页文件
   */
  saveTab(tabId: string): void {
    const tab = this.tabMap.get(tabId);
    if (tab) {
      tab.markSaved();
      tab.fileSize = tab.content.length;
      this.notifyListeners(TabStateEventType.TAB_SAVED, tab);
    }
  }

  /**
   * 更新标签页标签名
   */
  updateTabLabel(tabId: string, newLabel: string): void {
    const tab = this.tabMap.get(tabId);
    if (tab) {
      tab.label = newLabel;
      this.notifyListeners(TabStateEventType.LABEL_CHANGED, tab);
    }
  }

  /**
   * 检查是否存在未保存的修改
   */
  hasUnsavedChanges(): boolean {
    return this.tabs.some((t: TabModel) => t.isModified);
  }

  /**
   * 获取所有有未保存修改的标签页
   */
  getUnsavedTabs(): TabModel[] {
    return this.tabs.filter((t: TabModel) => t.isModified);
  }

  /**
   * 添加状态变更监听器
   */
  addListener(listener: TabStateChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  /**
   * 移除状态变更监听器
   */
  removeListener(listener: TabStateChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index !== -1) {
      this.listeners.splice(index, 1);
    }
  }

  /**
   * 通知所有监听器
   */
  private notifyListeners(event: TabStateEventType, tab: TabModel): void {
    for (let i = 0; i < this.listeners.length; i++) {
      const listener = this.listeners[i];
      listener.onTabStateChanged(event, tab);
    }
  }
}

/**
 * 标签页状态事件类型
 */
export enum TabStateEventType {
  TAB_OPENED = 'tabOpened',
  TAB_CLOSED = 'tabClosed',
  TAB_SWITCHED = 'tabSwitched',
  CONTENT_CHANGED = 'contentChanged',
  TAB_SAVED = 'tabSaved',
  LABEL_CHANGED = 'labelChanged'
}

/**
 * 标签页状态变更监听器接口
 */
export interface TabStateChangeListener {
  onTabStateChanged(event: TabStateEventType, tab: TabModel): void;
}
