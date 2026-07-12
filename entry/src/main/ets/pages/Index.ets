import { TabModel, TabStateManager, ProgrammingLanguage } from '../model/TabModel';
import { FileService } from '../service/FileService';
import { ThemeColors } from '../utils/ThemeColors';
import { EditorTabBarImpl as EditorTabBar, TabItem } from '../components/EditorTabBar';
import { EditorAreaImpl as EditorArea } from '../components/EditorArea';
import { FindReplaceBarImpl as FindReplaceBar } from '../components/FindReplaceBar';
import { StatusBarImpl as StatusBar } from '../components/StatusBar';
import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common, ConfigurationConstant, Configuration } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { TipsDialog } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { preferences } from '@kit.ArkData';

interface SessionTabRecord {
  id: string;
  label: string;
  filePath: string;
  content: string;
  language: string;
  isModified: boolean;
  encoding: string;
  cursorLine: number;
  cursorColumn: number;
}

interface SessionRecord {
  activeTabId: string;
  tabs: SessionTabRecord[];
}

/**
 * 灵动编辑器 - 主页面
 * 整合工具栏、标签栏、编辑区和状态栏
 * 严格遵循华为 HarmonyOS 设计指南，支持响应式布局
 */
@Entry
@Component
struct Index {
  // 标签页状态管理
  @State tabManager: TabStateManager = new TabStateManager();
  // 当前活动标签页ID
  @State activeId: string = '';
  // 查找替换对话框状态
  @State showFindDialog: boolean = false;
  @State findPosition: number = -1;
  @State searchMatches: number[] = [];
  @State currentSearchIdx: number = -1;
  @State searchLen: number = 0;
  @State foldAll: boolean = false;
  // 字体大小
  @StorageProp('fontSize') fontSize: number = 16;
  // Tab 宽度
  @StorageProp('tabSize') tabSize: number = 4;
  // 是否自动换行
  @StorageProp('wordWrap') wordWrap: boolean = false;
  // 是否显示行号
  @StorageProp('showLineNumbers') showLineNumbers: boolean = true;
  // 当前断点
  @StorageProp('currentBreakpoint') currentBreakpoint: string = 'md';
  // 窗口宽度
  @StorageProp('windowWidth') windowWidth: number = 360;
  // 深色模式标志
  @StorageProp('currentColorMode') currentColorMode: string = 'light';
  @State readOnly: boolean = false;
  @StorageProp('fullscreen') fullscreen: boolean = false;
  @StorageProp('selectionStats') selectionStats: string = '';

  /**
   * 主题颜色快捷访问。
   * 每次 UI 刷新时调用，确保响应深色/亮色切换。
   */
  private col(): ThemeColors {
    return ThemeColors.forMode(this.currentColorMode);
  }

  // ================================================================
  // 状态栏信息
  // ================================================================
  @State cursorPulse: number = 1.0;
  @State fileEncoding: string = 'UTF-8';
  @State fileType: string = '纯文本';
  @State currentLanguage: string = 'plaintext';
  @State insertMode: boolean = true;
  private autoSaveTimer: number = -1;
  @State cursorLine: number = 1;
  @State cursorColumn: number = 1;
  @State totalLines: number = 1;
  @State totalChars: number = 0;
  @State showGoToLine: boolean = false;
  @State goToLineInput: string = '';

  // 最近文件列表
  private recentFiles: string[] = [];
  private recentMax: number = 10;
  private recentPrefs: preferences.Preferences | undefined = undefined;

  private async initRecentFiles(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      this.recentPrefs = await preferences.getPreferences(ctx, 'recent_files');
      const data = this.recentPrefs.getSync('uris', '');
      if (data && typeof data === 'string' && data.length > 0) {
        this.recentFiles = data.split('|');
      }
    } catch (_) {}
  }

  private addRecentFile(uri: string): void {
    const idx = this.recentFiles.indexOf(uri);
    if (idx >= 0) {
      this.recentFiles.splice(idx, 1);
    }
    this.recentFiles.unshift(uri);
    if (this.recentFiles.length > this.recentMax) {
      this.recentFiles.pop();
    }
    this.persistRecentFiles();
  }

  private persistRecentFiles(): void {
    if (this.recentPrefs) {
      this.recentPrefs.putSync('uris', this.recentFiles.join('|'));
      this.recentPrefs.flush();
    }
  }

  // 关于弹窗
  private aboutDialogController: CustomDialogController | undefined = new CustomDialogController({
    builder: this.aboutDialogBuilder,
    autoCancel: true,
    alignment: DialogAlignment.Center,
    cornerRadius: 16
  });

  private donateWechatController: CustomDialogController | undefined = new CustomDialogController({
    builder: this.donateWechatBuilder,
    autoCancel: true,
    alignment: DialogAlignment.Center,
    cornerRadius: 16
  });

  private donateAlipayController: CustomDialogController | undefined = new CustomDialogController({
    builder: this.donateAlipayBuilder,
    autoCancel: true,
    alignment: DialogAlignment.Center,
    cornerRadius: 16
  });

  aboutToAppear(): void {
    AppStorage.setOrCreate('wordWrap', true);
    AppStorage.setOrCreate('fontSize', 16);
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const dark = ctx.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      AppStorage.setOrCreate('currentColorMode', dark ? 'dark' : 'light');
      window.getLastWindow(ctx).then((w) => {
        AppStorage.setOrCreate('mainWindow', w);
        w.setWindowTitle('LivelyNotepad');
      });
    } catch (_) {
      AppStorage.setOrCreate('currentColorMode', 'light');
    }
    this.restoreSession();
    this.initRecentFiles();
  }

  private applySystemColorMode(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const dark = ctx.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      AppStorage.setOrCreate('currentColorMode', dark ? 'dark' : 'light');
    } catch (e) {
      AppStorage.setOrCreate('currentColorMode', 'light');
    }
  }

  aboutToDisappear(): void {
    this.aboutDialogController = undefined;
    this.donateWechatController = undefined;
    this.donateAlipayController = undefined;
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    const dark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, () => {
      AppStorage.setOrCreate('currentColorMode', dark ? 'dark' : 'light');
    });
  }

  // ==================== 会话持久化（内联实现，避免外部编译依赖） ====================

  private getSessionPath(): string {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      return ctx.filesDir + '/session_backup.json';
    } catch (_) {
      return '/data/session_backup.json';
    }
  }

  private saveSession(): void {
    try {
      const tabs = this.tabManager.getAllTabs();
      const path = this.getSessionPath();
      if (tabs.length === 0) {
        // 无标签时删除会话文件，下次启动显示欢迎页
        try { fileIo.unlinkSync(path); } catch (e) { /* 文件本就不存在 */ }
        return;
      }
      const tabRecords: SessionTabRecord[] = [];
      for (let i = 0; i < tabs.length; i++) {
        const t = tabs[i];
        tabRecords.push({
          id: t.id,
          label: t.label,
          filePath: t.filePath,
          content: t.content,
          language: t.language,
          isModified: t.isModified,
          encoding: t.encoding,
          cursorLine: t.cursorLine,
          cursorColumn: t.cursorColumn
        } as SessionTabRecord);
      }
      const data: SessionRecord = { activeTabId: this.activeId, tabs: tabRecords };
      const json = JSON.stringify(data);
      if (json === undefined) {
        return;
      }
      let file: fileIo.File | undefined;
      try {
        file = fileIo.openSync(
          path,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC
        );
        fileIo.writeSync(file.fd, json);
        fileIo.fsyncSync(file.fd);
      } finally {
        if (file) {
          try { fileIo.closeSync(file); } catch (e) { /* 静默 */ }
        }
      }
    } catch (e) {
      // 静默失败
    }
  }

  private restoreSession(): void {
    const path = this.getSessionPath();
    let file: fileIo.File | undefined;
    try {
      file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(path);
      if (stat.size > 0) {
        const buf = new ArrayBuffer(stat.size);
        const readLen = fileIo.readSync(file.fd, buf);
        if (readLen > 0) {
          const decoder = new util.TextDecoder('utf-8');
          const json = decoder.decodeToString(new Uint8Array(buf, 0, readLen));
          const data: SessionRecord = JSON.parse(json) as SessionRecord;
          if (data !== null && data.tabs !== undefined && data.tabs.length > 0) {
            const tabsArr = data.tabs;
            for (let i = 0; i < tabsArr.length; i++) {
              const st = tabsArr[i];
              const tab = new TabModel(
                st.id, st.label, st.filePath,
                st.content, st.language as ProgrammingLanguage
              );
              tab.encoding = st.encoding;
              tab.cursorLine = st.cursorLine;
              tab.cursorColumn = st.cursorColumn;
              tab.isModified = st.isModified;
              this.tabManager.tabs.push(tab);
            }
            this.tabManager.activeTabId = data.activeTabId;
            this.activeId = data.activeTabId;
            this.tabManager.rebuildTabMap();
          }
        }
      }
    } catch (e) {
      // 首次启动无缓存文件
    } finally {
      if (file) {
        try { fileIo.closeSync(file); } catch (e) { /* 静默 */ }
      }
    }
  }

  onPageShow(): void {
    // 每次显示时刷新
  }

  /**
   * 获取当前活动标签页
   */
  private getActiveTab(): TabModel | undefined {
    return this.tabManager.getActiveTab();
  }

  private getActiveTabContent(): string {
    const tab = this.tabManager.getActiveTab();
    return tab ? tab.content : '';
  }

  private getActiveTabModified(): boolean {
    const tab = this.tabManager.getActiveTab();
    return tab ? tab.isModified : false;
  }

  /**
   * 转换为TabItem列表供EditorTabBar使用
   */
  private getTabItems(): TabItem[] {
    const items: TabItem[] = [];
    const tabs = this.tabManager.getAllTabs();
    for (let i = 0; i < tabs.length; i++) {
      const tab = tabs[i];
      items.push({
        id: tab.id,
        title: tab.label,
        isModified: tab.isModified,
        filePath: tab.filePath,
        language: tab.language
      });
    }
    return items;
  }

  // ==================== 工具栏操作 ====================

  /** 新建文件 */
  private onNewFile(): void {
    const count = this.tabManager.getTabCount();
    const tab = this.tabManager.createNewTab('新建文件 ' + (count + 1), '', '');
    this.getUIContext().animateTo({ duration: 250, curve: Curve.Smooth }, () => {
      this.activeId = tab.id;
    });
  }

  /** 打开文件 */
  private onOpenFile(): void {
    try {
      const documentPicker = new picker.DocumentViewPicker();
      documentPicker.select().then((result: Object): void => {
        const uris = result as string[];
        if (Array.isArray(uris) && uris.length > 0) {
          const uri = uris[0];
          FileService.readFile(uri).then((content: string): void => {
            const fileName = FileService.getFileName(uri);
            const tab = this.tabManager.openFile(fileName, uri, content);
            this.activeId = tab.id;
            this.addRecentFile(uri);
            this.updateStatusBar();
          }).catch((err: Error): void => {
          });
        }
      }).catch((err: Error): void => {
      });
    } catch (err) {
    }
  }

  /** 另存为（公开） */
  private onSaveFileAs(): void {
    this.onSaveAsFile();
  }

  /** 保存文件 */
  private onSaveFile(): void {
    const tab = this.getActiveTab();
    if (!tab) {
      return;
    }
    const raw = tab.content;
    const lines = raw.split('\n');
    const cleaned: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      let line = lines[i];
      let end = line.length;
      while (end > 0 && (line.charAt(end - 1) === ' ' || line.charAt(end - 1) === '\t')) {
        end--;
      }
      cleaned.push(line.substring(0, end));
    }
    const cleanContent = cleaned.join('\n');
    if (cleanContent !== raw) {
      this.tabManager.updateTabContent(tab.id, cleanContent);
    }
    if (tab.filePath) {
      FileService.writeFile(tab.filePath, cleanContent).then((): void => {
        this.tabManager.saveTab(tab.id);
        this.updateStatusBar();
      }).catch((err: Error): void => {
      });
    } else {
      this.onSaveAsFile();
    }
  }

  /** 另存为 */
  private onSaveAsFile(): void {
    const tab = this.getActiveTab();
    if (!tab) {
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker();
      documentPicker.save({ newFileNames: [tab.label] }).then((result: Object): void => {
        if (result) {
          const uris = result as string[];
          if (Array.isArray(uris) && uris.length > 0) {
            const uri = uris[0];
            FileService.writeFile(uri, tab.content).then((): void => {
              tab.filePath = uri;
              tab.label = FileService.getFileName(uri);
              this.tabManager.saveTab(tab.id);
              this.updateStatusBar();
            }).catch((err: Error): void => {
            });
          }
        }
      }).catch((err: Error): void => {
      });
    } catch (err) {
    }
  }

  /** 全部保存（公开） */
  /** 撤销 */
  private onUndo(): void {
    const tab = this.getActiveTab();
    if (tab) {
      const restored = this.tabManager.undo(tab.id);
      if (restored !== null) {
        this.tabManager.updateTabContent(tab.id, restored);
        this.updateStatusBar();
      }
    }
  }

  /** 重做 */
  private onRedo(): void {
    const tab = this.getActiveTab();
    if (tab) {
      const restored = this.tabManager.redo(tab.id);
      if (restored !== null) {
        this.tabManager.updateTabContent(tab.id, restored);
        this.updateStatusBar();
      }
    }
  }

  /** 切换查找替换 */
  private onFindReplace(): void {
    this.showFindDialog = !this.showFindDialog;
    if (!this.showFindDialog) {
      this.searchMatches = [];
      this.currentSearchIdx = -1;
      this.searchLen = 0;
    }
  }

  /** 字体放大 */
  private zoomIn(): void {
    const newSize: number = Math.min(36, this.fontSize + 2);
    AppStorage.setOrCreate('fontSize', newSize);
  }

  /** 字体缩小 */
  private zoomOut(): void {
    const newSize: number = Math.max(8, this.fontSize - 2);
    AppStorage.setOrCreate('fontSize', newSize);
  }

  /** 还原字体 */
  private zoomReset(): void {
    AppStorage.setOrCreate('fontSize', 16);
  }

  /** 切换自动换行 */
  private toggleWordWrap(): void {
    AppStorage.setOrCreate('wordWrap', !this.wordWrap);
  }

  private toggleFoldAll(): void {
    this.foldAll = !this.foldAll;
    AppStorage.setOrCreate('foldAll', this.foldAll);
  }

  /** 切换暗色/亮色主题 */
  private toggleTheme(): void {
    const newMode = this.currentColorMode === 'dark' ? 'light' : 'dark';
    this.getUIContext().animateTo({ duration: 300, curve: Curve.Smooth }, () => {
      AppStorage.setOrCreate('currentColorMode', newMode);
    });
  }

  /** 插入当前日期时间 */
  private insertDateTime(): void {
    const tab = this.getActiveTab();
    if (tab) {
      const now = new Date();
      const ds = now.getFullYear() + '-' +
        String(now.getMonth() + 1).padStart(2, '0') + '-' +
        String(now.getDate()).padStart(2, '0') + ' ' +
        String(now.getHours()).padStart(2, '0') + ':' +
        String(now.getMinutes()).padStart(2, '0');
      const newContent = tab.content + ds;
      this.tabManager.pushUndo(tab.id, tab.content);
      this.tabManager.updateTabContent(tab.id, newContent);
      this.saveSession();
    }
  }

  /** 复制当前行（参考 Notepad++ Ctrl+D） */
  private duplicateLine(): void {
    const tab = this.getActiveTab();
    if (!tab || !tab.content) {
      return;
    }
    const lineIdx = tab.cursorLine;
    const lines = tab.content.split('\n');
    if (lineIdx < 0 || lineIdx >= lines.length) {
      return;
    }
    const newLines: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      newLines.push(lines[i]);
      if (i === lineIdx) {
        newLines.push(lines[lineIdx]);
      }
    }
    const newContent = newLines.join('\n');
    this.tabManager.pushUndo(tab.id, tab.content);
    this.tabManager.updateTabContent(tab.id, newContent);
    this.saveSession();
  }

  /** 删除当前行（参考 Notepad++ Ctrl+L） */
  private deleteLine(): void {
    const tab = this.getActiveTab();
    if (!tab || !tab.content) {
      return;
    }
    const lineIdx = tab.cursorLine;
    const lines = tab.content.split('\n');
    if (lineIdx < 0 || lineIdx >= lines.length) {
      return;
    }
    if (lines.length <= 1) {
      this.tabManager.updateTabContent(tab.id, '');
      this.saveSession();
      return;
    }
    const newLines: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      if (i !== lineIdx) {
        newLines.push(lines[i]);
      }
    }
    const newContent = newLines.join('\n');
    this.tabManager.pushUndo(tab.id, tab.content);
    this.tabManager.updateTabContent(tab.id, newContent);
    this.saveSession();
  }

  /** 选中/全文转大写 */
  private toUpperCase(): void {
    const tab = this.getActiveTab();
    if (!tab) {
      return;
    }
    this.tabManager.pushUndo(tab.id, tab.content);
    this.tabManager.updateTabContent(tab.id, tab.content.toUpperCase());
    this.saveSession();
  }

  /** 选中/全文转小写 */
  private toLowerCase(): void {
    const tab = this.getActiveTab();
    if (!tab) {
      return;
    }
    this.tabManager.pushUndo(tab.id, tab.content);
    this.tabManager.updateTabContent(tab.id, tab.content.toLowerCase());
    this.saveSession();
  }

  /** 移除行尾空格（参考 VS Code Trim Trailing Whitespace） */
  private trimTrailingWhitespace(): void {
    const tab = this.getActiveTab();
    if (!tab || !tab.content) {
      return;
    }
    const lines = tab.content.split('\n');
    const trimmed: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      let line = lines[i];
      let end = line.length - 1;
      while (end >= 0 && (line.charAt(end) === ' ' || line.charAt(end) === '\t')) {
        end--;
      }
      trimmed.push(line.substring(0, end + 1));
    }
    const newContent = trimmed.join('\n');
    if (newContent !== tab.content) {
      this.tabManager.pushUndo(tab.id, tab.content);
      this.tabManager.updateTabContent(tab.id, newContent);
      this.saveSession();
    }
  }

  /** 制表符转为空格 */
  private tabsToSpaces(): void {
    const tab = this.getActiveTab();
    if (!tab || !tab.content) {
      return;
    }
    let spaces = '';
    for (let i = 0; i < this.tabSize; i++) spaces += ' ';
    const newContent = tab.content.split('\t').join(spaces);
    if (newContent !== tab.content) {
      this.tabManager.pushUndo(tab.id, tab.content);
      this.tabManager.updateTabContent(tab.id, newContent);
      this.saveSession();
    }
  }

  /** 排序行（参考 Notepad++ Edit → Line Operations → Sort Lines） */
  private sortLines(): void {
    const tab = this.getActiveTab();
    if (!tab || !tab.content) {
      return;
    }
    const lines = tab.content.split('\n');
    lines.sort();
    const newContent = lines.join('\n');
    if (newContent !== tab.content) {
      this.tabManager.pushUndo(tab.id, tab.content);
      this.tabManager.updateTabContent(tab.id, newContent);
      this.saveSession();
    }
  }

  /** 去重行：移除重复行，保留首次出现 */
  private uniqueLines(): void {
    const tab = this.getActiveTab();
    if (!tab || !tab.content) return;
    const lines = tab.content.split('\n');
    const seen = new Set<string>();
    const result: string[] = [];
    for (const l of lines) {
      if (!seen.has(l)) {
        seen.add(l);
        result.push(l);
      }
    }
    const newContent = result.join('\n');
    if (newContent !== tab.content) {
      this.tabManager.pushUndo(tab.id, tab.content);
      this.tabManager.updateTabContent(tab.id, newContent);
      this.saveSession();
    }
  }

  /** 删除空行 */
  private deleteEmptyLines(): void {
    const tab = this.getActiveTab();
    if (!tab || !tab.content) return;
    const lines = tab.content.split('\n');
    const filtered: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      // 手动 trim 行首行尾空白（避免 RegExp）
      let line = lines[i];
      let s = 0;
      let e = line.length;
      // 跳过行首空白
      while (s < e) {
        const c = line.charCodeAt(s);
        if (c === 32 || c === 9) {
          s++;
        } else {
          break;
        }
      }
      // 跳过行尾空白
      while (e > s) {
        const c = line.charCodeAt(e - 1);
        if (c === 32 || c === 9) {
          e--;
        } else {
          break;
        }
      }
      if (e - s > 0) filtered.push(lines[i]);
    }
    const newContent = filtered.join('\n');
    if (newContent !== tab.content) {
      this.tabManager.pushUndo(tab.id, tab.content);
      this.tabManager.updateTabContent(tab.id, newContent);
      this.saveSession();
    }
  }

  /** 上移当前行 */
  private moveLineUp(): void {
    const tab = this.getActiveTab();
    if (!tab || !tab.content) {
      return;
    }
    const idx = tab.cursorLine;
    const lines = tab.content.split('\n');
    if (idx <= 0 || idx >= lines.length) {
      return;
    }
    const tmp = lines[idx];
    lines[idx] = lines[idx - 1];
    lines[idx - 1] = tmp;
    const newContent = lines.join('\n');
    this.tabManager.pushUndo(tab.id, tab.content);
    this.tabManager.updateTabContent(tab.id, newContent);
    tab.cursorLine = idx - 1;
    this.saveSession();
  }

  /** 下移当前行 */
  private moveLineDown(): void {
    const tab = this.getActiveTab();
    if (!tab || !tab.content) {
      return;
    }
    const idx = tab.cursorLine;
    const lines = tab.content.split('\n');
    if (idx < 0 || idx >= lines.length - 1) {
      return;
    }
    const tmp = lines[idx];
    lines[idx] = lines[idx + 1];
    lines[idx + 1] = tmp;
    const newContent = lines.join('\n');
    this.tabManager.pushUndo(tab.id, tab.content);
    this.tabManager.updateTabContent(tab.id, newContent);
    tab.cursorLine = idx + 1;
    this.saveSession();
  }

  // ==================== 标签栏操作 ====================

  /** 切换标签 */
  private onTabSwitch(tabId: string): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.Smooth }, () => {
      this.activeId = tabId;
      this.tabManager.setActiveTab(tabId);
    });
    this.updateStatusBar();
  }

  /** 关闭标签 */
  private onTabClose(tabId: string): void {
    const tab = this.tabManager.getTabById(tabId);
    if (tab && tab.isModified) {
      this.getUIContext().getPromptAction().showDialog({
        title: '未保存的更改',
        message: '文件 "' + tab.label + '" 有未保存的更改，是否关闭？',
        buttons: [
          { text: '关闭', color: this.col().danger },
          { text: '取消', color: this.col().textSecondary }
        ]
      }).then((result) => {
        if (result.index === 0) {
          this.doCloseTab(tabId);
        }
      }).catch(() => {});
    } else {
      this.doCloseTab(tabId);
    }
  }

  private doCloseTab(tabId: string): void {
    this.tabManager.closeTab(tabId);
    const active = this.tabManager.getActiveTab();
    if (active) {
      this.activeId = active.id;
    } else {
      this.activeId = '';
    }
    this.updateStatusBar();
    this.saveSession();
  }

  private closeOtherTabs(tabId: string): void {
    const otherIds: string[] = [];
    const tabs = this.tabManager.getAllTabs();
    for (let i = 0; i < tabs.length; i++) {
      if (tabs[i].id !== tabId) {
        otherIds.push(tabs[i].id);
      }
    }
    for (let i = 0; i < otherIds.length; i++) {
      this.tabManager.closeTab(otherIds[i]);
    }
    this.activeId = tabId;
    this.updateStatusBar();
    this.saveSession();
  }

  private closeAllTabs(): void {
    const ids: string[] = [];
    const tabs = this.tabManager.getAllTabs();
    for (let i = 0; i < tabs.length; i++) {
      ids.push(tabs[i].id);
    }
    for (let i = 0; i < ids.length; i++) {
      this.tabManager.closeTab(ids[i]);
    }
    this.activeId = '';
    this.updateStatusBar();
    this.saveSession();
  }

  // ==================== 编辑区操作 ====================

  /** 文本内容变更 */
  private onContentChange(content: string): void {
    const tab = this.getActiveTab();
    if (tab && tab.id === this.activeId) {
      // 变更前保存快照用于撤销
      this.tabManager.pushUndo(tab.id, tab.content);
      this.tabManager.updateTabContent(tab.id, content);
      // 实时更新字数统计 + 持久化会话
      this.totalLines = content ? Math.max(1, content.split('\n').length) : 1;
      this.totalChars = content.length;
      this.saveSession();
      // 自动保存（3 秒无操作后保存有路径的文件）
      if (tab.filePath) {
        clearTimeout(this.autoSaveTimer);
        this.autoSaveTimer = setTimeout(() => { this.onSaveFile(); }, 3000);
      }
    }
  }

  /** 更新状态栏 */
  private updateStatusBar(): void {
    const tab = this.getActiveTab();
    if (tab) {
      this.fileEncoding = tab.encoding;
      this.fileType = this.getLanguageName(tab.language);
      this.currentLanguage = tab.language;
      this.cursorLine = tab.cursorLine + 1;
      this.cursorColumn = tab.cursorColumn + 1;
      this.totalLines = tab.content ? Math.max(1, tab.content.split('\n').length) : 1;
      this.totalChars = tab.content ? tab.content.length : 0;
      // 更新窗口标题
      const mod = tab.isModified ? ' ● ' : '';
      this.setWindowTitle(tab.label + mod + ' - LivelyNotepad');
    } else {
      this.setWindowTitle('LivelyNotepad');
    }
    // 每次状态更新时自动缓存会话
    this.saveSession();
  }

  private eolDisplay(): string {
    const tab = this.getActiveTab();
    if (!tab) return 'LF';
    const le = tab.content.includes('\r\n') ? 'CRLF' :
      tab.content.includes('\r') ? 'CR' : 'LF';
    return le;
  }

  private toggleEOL(): void {
    const tab = this.getActiveTab();
    if (!tab || !tab.content) return;
    const cur = tab.content.includes('\r\n') ? 'CRLF' :
      tab.content.includes('\r') ? 'CR' : 'LF';
    let lines: string[] = [];
    let idx = 0;
    const src = tab.content;
    while (idx < src.length) {
      let start = idx;
      while (idx < src.length && src.charAt(idx) !== '\n' && src.charAt(idx) !== '\r') {
        idx++;
      }
      lines.push(src.substring(start, idx));
      if (idx < src.length && src.charAt(idx) === '\r') {
        idx++;
      }
      if (idx < src.length && src.charAt(idx) === '\n') {
        idx++;
      }
    }
    this.tabManager.pushUndo(tab.id, tab.content);
    if (cur === 'LF') {
      this.tabManager.updateTabContent(tab.id, lines.join('\r\n'));
    } else if (cur === 'CRLF') {
      this.tabManager.updateTabContent(tab.id, lines.join('\r'));
    } else {
      this.tabManager.updateTabContent(tab.id, lines.join('\n'));
    }
    this.saveSession();
  }

  private setWindowTitle(title: string): void {
    try {
      const w = AppStorage.get<window.Window>('mainWindow');
      if (w) {
        w.setWindowTitle(title);
      }
    } catch (_) {}
  }

  /**
   * 将 ProgrammingLanguage 枚举值映射为中文显示名称。
   * 用于状态栏和语言菜单显示。
   */
  private getLanguageName(lang: ProgrammingLanguage): string {
    const map = new Map<string, string>();
    // 前端 / Web
    map.set('javascript', 'JavaScript');
    map.set('typescript', 'TypeScript');
    map.set('arkts', 'ArkTS');
    map.set('html', 'HTML');
    map.set('css', 'CSS');
    map.set('json', 'JSON');
    map.set('xml', 'XML');
    map.set('markdown', 'Markdown');
    // 后端语言
    map.set('python', 'Python');
    map.set('java', 'Java');
    map.set('c', 'C');
    map.set('cpp', 'C++');
    map.set('csharp', 'C#');
    map.set('go', 'Go');
    map.set('rust', 'Rust');
    map.set('swift', 'Swift');
    map.set('sql', 'SQL');
    // 脚本 / 配置
    map.set('shell', 'Shell');
    map.set('yaml', 'YAML');
    map.set('toml', 'TOML');
    map.set('plaintext', '纯文本');
    const name = map.get(lang);
    return name !== undefined ? name : '纯文本';
  }

  // ==================== 主布局 ====================

  build() {
    Column() {
      // 顶部工具栏（全屏隐藏）
      if (!this.fullscreen) {
        this.buildToolbar()

        // 标签栏
        Column() {
        EditorTabBar({
          tabs: this.getTabItems(),
          activeTabId: this.activeId,
          onTabClick: (tabId: string): void => { this.onTabSwitch(tabId); },
          onTabClose: (tabId: string): void => { this.onTabClose(tabId); },
          onCloseOthers: (tabId: string): void => { this.closeOtherTabs(tabId); },
          onCloseAll: (): void => { this.closeAllTabs(); },
          onNewTab: (): void => { this.onNewFile(); }
        })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .tabIndex(-1)
      } // end if(!fullscreen)

      // 查找替换栏（顶部固定）
      if (this.showFindDialog) {
        FindReplaceBar({
          editorText: this.getActiveTabContent(),
          onClose: (): void => {
            this.showFindDialog = false;
            this.searchMatches = [];
            this.currentSearchIdx = -1;
            this.searchLen = 0;
          },
          onReplace: (newText: string): void => {
            const tab = this.getActiveTab();
            if (tab) {
              this.tabManager.updateTabContent(tab.id, newText);
              this.saveSession();
            }
          },
          onFindJump: (pos: number, _len: number): void => {
            this.findPosition = pos;
          },
          onSearchUpdate: (matches: number[], idx: number, len: number): void => {
            this.searchMatches = [...matches];
            this.currentSearchIdx = idx;
            this.searchLen = len;
          }
        })
        .transition(
          TransitionEffect.asymmetric(
            TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.Smooth })
              .combine(TransitionEffect.translate({ y: -25 })),
            TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.Sharp })
              .combine(TransitionEffect.translate({ y: -30 }))
          )
        )
      }

      // 编辑区域
      if (this.activeId) {
        EditorArea({
          tabId: this.activeId,
          language: this.currentLanguage,
          content: this.getActiveTabContent(),
          findPosition: this.findPosition,
          foldAll: this.foldAll,
          searchMatches: this.searchMatches,
          currentSearchIdx: this.currentSearchIdx,
          searchLen: this.searchLen,
          isModified: this.getActiveTabModified(),
          readOnly: this.readOnly,
          onContentChange: (content: string): void => { this.onContentChange(content); },
          onCursorMove: (line: number, column: number): void => {
            this.cursorLine = line;
            this.cursorColumn = column;
            if (this.cursorPulse === 1.0) {
              this.cursorPulse = 1.08;
              setTimeout(() => { this.cursorPulse = 1.0; }, 120);
            }
            const tab = this.getActiveTab();
            if (tab) {
              tab.cursorLine = line - 1;
              tab.cursorColumn = column - 1;
            }
          },
          onLanguageDetect: (lang: string): void => {
            const tab = this.getActiveTab();
            if (tab) {
              tab.language = lang as ProgrammingLanguage;
              this.currentLanguage = lang;
              this.fileType = this.getLanguageName(lang as ProgrammingLanguage);
            }
          },
          onSave: (): void => { this.onSaveFile(); },
          onFindReplace: (): void => { this.onFindReplace(); },
          onGoToLine: (): void => { this.showGoToLine = true; },
          onUndo: (): void => { this.onUndo(); },
          onRedo: (): void => { this.onRedo(); },
          onDuplicateLine: (): void => { this.duplicateLine(); },
          onDeleteLine: (): void => { this.deleteLine(); },
          onMoveLineUp: (): void => { this.moveLineUp(); },
          onMoveLineDown: (): void => { this.moveLineDown(); }
        })
          .layoutWeight(1)
      } else {
        // VS Code 风格欢迎页
        Column() {
          Column() {
            Text('LivelyNotepad')
              .fontSize(this.fontSize * 2.5)
              .fontWeight(FontWeight.Lighter)
              .fontColor(this.col().text)
              .fontFamily('sans-serif')

            Text('灵动编辑器')
              .fontSize(this.fontSize * 1.1)
              .fontColor(this.col().textSecondary)
              .margin({ top: 4, bottom: 32 })

            Row() {
              Button('新建文件')
                .fontSize(this.fontSize * 0.9)
                .fontColor(Color.White)
                .backgroundColor(this.col().accent)
                .type(ButtonType.Normal)
                .height(36)
                .borderRadius(2)
                .padding({ left: 16, right: 16 })
                .onClick(() => { this.onNewFile(); })
              Button('打开文件')
                .fontSize(this.fontSize * 0.9)
                .fontColor(this.col().text)
                .backgroundColor(this.col().surface)
                .type(ButtonType.Normal)
                .height(36)
                .borderRadius(2)
                .padding({ left: 16, right: 16 })
                .margin({ left: 12 })
                .onClick(() => { this.onOpenFile(); })
            }

            // 快捷键提示
            Column() {
              Text('快捷键').fontSize(this.fontSize * 0.7).fontWeight(FontWeight.Bold)
                .fontColor(this.col().textSecondary).margin({ top: 32, bottom: 8 })
              Row() {
                Text('Ctrl+N').fontSize(this.fontSize * 0.7).fontColor(this.col().accent).width(80)
                Text('新建').fontSize(this.fontSize * 0.7).fontColor(this.col().textSecondary)
              }.padding({ top: 2, bottom: 2 })
              Row() {
                Text('Ctrl+O').fontSize(this.fontSize * 0.7).fontColor(this.col().accent).width(80)
                Text('打开').fontSize(this.fontSize * 0.7).fontColor(this.col().textSecondary)
              }.padding({ top: 2, bottom: 2 })
              Row() {
                Text('Ctrl+S').fontSize(this.fontSize * 0.7).fontColor(this.col().accent).width(80)
                Text('保存').fontSize(this.fontSize * 0.7).fontColor(this.col().textSecondary)
              }.padding({ top: 2, bottom: 2 })
              Row() {
                Text('Ctrl+Shift+P').fontSize(this.fontSize * 0.7).fontColor(this.col().accent).width(80)
                Text('命令面板').fontSize(this.fontSize * 0.7).fontColor(this.col().textSecondary)
              }.padding({ top: 2, bottom: 2 })
            }
          }
          .alignItems(HorizontalAlign.Center)
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(this.col().bg)
        .justifyContent(FlexAlign.Center)
      }

      // 状态栏（全屏隐藏）
      if (!this.fullscreen) {
        this.buildStatusBar()
      }

      // Go to Line 快捷输入（状态栏上方）
      if (this.showGoToLine) {
        this.goToLineOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.col().bg)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      // 响应式断点检测
      const width: number = Number(newArea.width);
      if (width < 600) {
        AppStorage.setOrCreate('currentBreakpoint', 'sm');
      } else if (width < 840) {
        AppStorage.setOrCreate('currentBreakpoint', 'md');
      } else {
        AppStorage.setOrCreate('currentBreakpoint', 'lg');
      }
      AppStorage.setOrCreate('windowWidth', width);
    })
  }

  /** 跳转到指定行 */
  private doGoToLine(): void {
    const lineNum: number = parseInt(this.goToLineInput);
    if (isNaN(lineNum) || lineNum < 1 || lineNum > this.totalLines) {
      return;
    }
    this.cursorLine = lineNum;
    this.showGoToLine = false;
    this.goToLineInput = '';
  }

  private getCurrentLang(): ProgrammingLanguage {
    const tab = this.getActiveTab();
    return tab ? tab.language : ProgrammingLanguage.PLAIN_TEXT;
  }

  /** 语言切换菜单构建器。 */
  @Builder
  buildLangMenu() {
    Menu() {
      MenuItem({ content: '纯文本' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.PLAIN_TEXT); })
      MenuItem({ content: 'JavaScript' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.JAVASCRIPT); })
      MenuItem({ content: 'TypeScript' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.TYPESCRIPT); })
      MenuItem({ content: 'ArkTS' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.ARKTS); })
      MenuItem({ content: 'HTML' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.HTML); })
      MenuItem({ content: 'CSS' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.CSS); })
      MenuItem({ content: 'JSON' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.JSON); })
      MenuItem({ content: 'XML' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.XML); })
      MenuItem({ content: 'Markdown' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.MARKDOWN); })
      MenuItem({ content: 'Python' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.PYTHON); })
      MenuItem({ content: 'Java' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.JAVA); })
      MenuItem({ content: 'C' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.C); })
      MenuItem({ content: 'C++' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.CPP); })
      MenuItem({ content: 'C#' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.CSHARP); })
      MenuItem({ content: 'Go' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.GO); })
      MenuItem({ content: 'Rust' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.RUST); })
      MenuItem({ content: 'Swift' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.SWIFT); })
      MenuItem({ content: 'SQL' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.SQL); })
      MenuItem({ content: 'Shell' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.SHELL); })
      MenuItem({ content: 'YAML' })
        .onClick((): void => { this.applyLang(ProgrammingLanguage.YAML); })
    }
  }

  private applyLang(lang: ProgrammingLanguage): void {
    const tab = this.getActiveTab();
    if (tab) {
      tab.language = lang;
      this.fileType = this.getLanguageName(lang);
      this.currentLanguage = lang;
    }
  }

  /** 编码切换菜单构建器。 */
  @Builder
  buildEncodingMenu() {
    Menu() {
      MenuItem({ content: 'UTF-8' })
        .onClick((): void => { this.applyEncoding('UTF-8'); })
      MenuItem({ content: 'GBK' })
        .onClick((): void => { this.applyEncoding('GBK'); })
      MenuItem({ content: 'GB2312' })
        .onClick((): void => { this.applyEncoding('GB2312'); })
      MenuItem({ content: 'ISO-8859-1' })
        .onClick((): void => { this.applyEncoding('ISO-8859-1'); })
      MenuItem({ content: 'UTF-16' })
        .onClick((): void => { this.applyEncoding('UTF-16'); })
      MenuItem({ content: 'US-ASCII' })
        .onClick((): void => { this.applyEncoding('US-ASCII'); })
    }
  }

  private applyEncoding(enc: string): void {
    const tab = this.getActiveTab();
    if (!tab) return;
    tab.encoding = enc;
    this.fileEncoding = enc;
    // 如果有文件路径，用新编码重新读取
    if (tab.filePath) {
      FileService.readFile(tab.filePath, enc.toLowerCase()).then((content: string) => {
        this.tabManager.updateTabContent(tab.id, content);
        this.updateStatusBar();
      });
    }
  }

  /** 全部保存 */
  private onSaveAll(): void {
    const unsaved = this.tabManager.getUnsavedTabs();
    unsaved.forEach((tab: TabModel): void => {
      if (tab.filePath) {
        FileService.writeFile(tab.filePath, tab.content)
          .then((): void => {
            this.tabManager.saveTab(tab.id);
          })
          .catch((err: Error): void => {
          });
      }
    });
    this.updateStatusBar();
  }

  @Builder
  goToLineOverlay() {
    Row() {
      Text('转到行:')
        .fontSize(12)
        .margin({ right: 6 })
      TextInput({ text: this.goToLineInput, placeholder: '行号' })
        .fontSize(13)
        .width(80)
        .height(30)
        .type(InputType.Number)
        .onChange((value: string): void => {
          this.goToLineInput = value;
        })
        .onSubmit((): void => {
          this.doGoToLine();
        })
      Button('跳转')
        .fontSize(11)
        .height(28)
        .margin({ left: 6 })
        .onClick((): void => { this.doGoToLine(); })
      Button('✕')
        .fontSize(13)
        .height(28)
        .margin({ left: 4 })
        .onClick((): void => {
          this.showGoToLine = false;
          this.goToLineInput = '';
        })
    }
    .width('100%')
    .height(32)
    .padding({ left: 12, right: 8 })
    .backgroundColor(this.col().statusBarBg)
    .animation({ duration: 100, curve: Curve.Linear })
    .border({ width: { top: 1 }, color: this.col().border })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .transition(
      TransitionEffect.OPACITY.animation({ duration: 150, curve: Curve.Smooth })
        .combine(TransitionEffect.translate({ y: -32 }))
    )
  }

  // ================================================================
  // 菜单构建器（VS Code 风格菜单栏）
  // ================================================================

  /** 文件菜单：新建、打开、保存、最近打开。 */
  @Builder
  buildFileMenu() {
    Menu() {
      MenuItem({ content: '新建' })
        .onClick((): void => { this.onNewFile(); })
      MenuItem({ content: '打开...' })
        .onClick((): void => { this.onOpenFile(); })
      MenuItem({ content: '保存 (Ctrl+S)' })
        .onClick((): void => { this.onSaveFile(); })
      MenuItem({ content: '另存为...' })
        .onClick((): void => { this.onSaveFileAs(); })
      MenuItem({ content: '全部保存' })
        .onClick((): void => { this.onSaveAll(); })

      if (this.recentFiles.length > 0) {
        MenuItem({ content: '─────────────' }).enabled(false)
        MenuItem({ content: '最近打开' }).enabled(false)
        ForEach(this.recentFiles.slice(0, 5),
          (uri: string, _index: number) => {
            MenuItem({ content: FileService.getFileName(uri) })
              .onClick((): void => { this.openRecentFile(uri); })
          },
          (uri: string) => uri
        )
      }
    }
  }

  private openRecentFile(uri: string): void {
    FileService.readFile(uri).then((content: string): void => {
      const fileName = FileService.getFileName(uri);
      const tab = this.tabManager.openFile(fileName, uri, content);
      this.activeId = tab.id;
      this.addRecentFile(uri);
      this.updateStatusBar();
    }).catch((err: Error): void => {
    });
  }

  /** 编辑菜单：撤销、重做、行操作、插入日期。 */
  @Builder
  buildEditMenu() {
    Menu() {
      MenuItem({ content: '撤销 (Ctrl+Z)' })
        .onClick((): void => { this.onUndo(); })
      MenuItem({ content: '重做 (Ctrl+Y)' })
        .onClick((): void => { this.onRedo(); })
      MenuItem({ content: '复制行 (Shift+Alt+↓)' })
        .onClick((): void => { this.duplicateLine(); })
      MenuItem({ content: '删除行 (Ctrl+Shift+K)' })
        .onClick((): void => { this.deleteLine(); })
      MenuItem({ content: '上移行 (Alt+↑)' })
        .onClick((): void => { this.moveLineUp(); })
      MenuItem({ content: '下移行 (Alt+↓)' })
        .onClick((): void => { this.moveLineDown(); })
      MenuItem({ content: '插入日期' })
        .onClick((): void => { this.insertDateTime(); })
    }
  }

  /** 查看菜单：字体缩放、换行、折叠、主题、行号、Tab 宽度。 */
  @Builder
  buildViewMenu() {
    Menu() {
      MenuItem({ content: '放大' })
        .onClick((): void => { this.zoomIn(); })
      MenuItem({ content: '缩小' })
        .onClick((): void => { this.zoomOut(); })
      MenuItem({ content: '还原字体' })
        .onClick((): void => { this.zoomReset(); })
      MenuItem({ content: this.wordWrap ? '✓ 自动换行' : '自动换行' })
        .onClick((): void => { this.toggleWordWrap(); })
      MenuItem({ content: this.foldAll ? '✓ 全部折叠' : '全部折叠' })
        .onClick((): void => { this.toggleFoldAll(); })
      MenuItem({
        content: this.currentColorMode === 'dark' ? '亮色主题' : '暗色主题'
      }).onClick((): void => { this.toggleTheme(); })
      MenuItem({ content: this.showLineNumbers ? '✓ 行号' : '行号' })
        .onClick((): void => {
          AppStorage.setOrCreate('showLineNumbers', !this.showLineNumbers);
        })
      MenuItem({ content: 'Tab 宽度: ' + this.tabSize })
        .onClick((): void => {
          const sizes = [2, 4, 8];
          const idx = sizes.indexOf(this.tabSize);
          const next = sizes[(idx + 1) % sizes.length];
          AppStorage.setOrCreate('tabSize', next);
        })
      MenuItem({ content: this.readOnly ? '✓ 只读模式' : '只读模式' })
        .onClick((): void => { this.readOnly = !this.readOnly; })
      MenuItem({ content: this.fullscreen ? '✓ 全屏模式 (F11)' : '全屏模式 (F11)' })
        .onClick((): void => { this.fullscreen = !this.fullscreen; })
    }
  }

  /** 工具菜单：大小写转换、排序、空白处理。 */
  @Builder
  buildToolsMenu() {
    Menu() {
      MenuItem({ content: '转大写' })
        .onClick((): void => { this.toUpperCase(); })
      MenuItem({ content: '转小写' })
        .onClick((): void => { this.toLowerCase(); })
      MenuItem({ content: '排序行' })
        .onClick((): void => { this.sortLines(); })
      MenuItem({ content: '去重行' })
        .onClick((): void => { this.uniqueLines(); })
      MenuItem({ content: '删行尾空格' })
        .onClick((): void => { this.trimTrailingWhitespace(); })
      MenuItem({ content: 'Tab → 空格' })
        .onClick((): void => { this.tabsToSpaces(); })
      MenuItem({ content: '删空行' })
        .onClick((): void => { this.deleteEmptyLines(); })
    }
  }

  /** 帮助菜单：反馈、关于。 */
  @Builder
  buildHelpMenu() {
    Menu() {
      MenuItem({ content: '问题与建议' })
        .onClick((): void => { this.showFeedback(); })
      MenuItem({ content: '微信捐助' })
        .onClick((): void => { this.showDonateWechat(); })
      MenuItem({ content: '支付宝捐助' })
        .onClick((): void => { this.showDonateAlipay(); })
      MenuItem({ content: '关于' })
        .onClick((): void => { this.showAbout(); })
    }
  }

  private showFeedback(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '问题与建议',
      message: '如有问题或改进建议，欢迎发送邮件至：\n\nazazaz0413@petalmail.com',
      buttons: [
        { text: '复制邮箱', color: this.col().accent },
        { text: '关闭', color: this.col().textSecondary }
      ]
    }).then((result) => {
      if (result.index === 0) {
        const pasteData = pasteboard.createData(
          pasteboard.MIMETYPE_TEXT_PLAIN,
          'azazaz0413@petalmail.com'
        );
        const systemPasteboard = pasteboard.getSystemPasteboard();
        systemPasteboard.setData(pasteData);
      }
    }).catch(() => {});
  }

  private showAbout(): void {
    if (this.aboutDialogController !== undefined) {
      this.aboutDialogController.open();
    }
  }

  @Builder
  aboutDialogBuilder() {
    TipsDialog({
      imageRes: $r('app.media.startIcon'),
      imageSize: { width: 80, height: 80 },
      title: '灵动编辑器',
      content: 'Lively Notepad\n\n版本 1.0.1\n\n仿 Notepad++ 与 VS Code 风格的\nHarmonyOS 轻量级代码编辑器',
      primaryButton: {
        value: '关闭',
        action: () => {
          if (this.aboutDialogController !== undefined) {
            this.aboutDialogController.close();
          }
        }
      }
    })
  }

  private showDonateWechat(): void {
    if (this.donateWechatController !== undefined) {
      this.donateWechatController.open();
    }
  }

  @Builder
  donateWechatBuilder() {
    TipsDialog({
      imageRes: $r('app.media.wechat_qr'),
      imageSize: { width: 'auto', height: 180 },
      title: '微信捐助',
      content: '感谢您的支持，扫描二维码进行捐助',
      primaryButton: {
        value: '关闭',
        action: () => {
          if (this.donateWechatController !== undefined) {
            this.donateWechatController.close();
          }
        }
      }
    })
  }

  private showDonateAlipay(): void {
    if (this.donateAlipayController !== undefined) {
      this.donateAlipayController.open();
    }
  }

  @Builder
  donateAlipayBuilder() {
    TipsDialog({
      imageRes: $r('app.media.alipay_qr'),
      imageSize: { width: 'auto', height: 180 },
      title: '支付宝捐助',
      content: '感谢您的支持，扫描二维码进行捐助',
      primaryButton: {
        value: '关闭',
        action: () => {
          if (this.donateAlipayController !== undefined) {
            this.donateAlipayController.close();
          }
        }
      }
    })
  }

  /**
   * 顶部菜单栏。
   * 包含：文件 / 编辑 / 查看 / 工具 / 帮助 下拉菜单按钮，以及查找按钮。
   */
  @Builder
  buildToolbar() {
    Row() {
      Button('文件')
        .fontSize(12)
        .fontColor(this.col().text)
        .backgroundColor(Color.Transparent)
        .type(ButtonType.Capsule)
        .height(28)
        .padding({ left: 8, right: 8 })
        .focusable(false)
        .bindMenu(this.buildFileMenu)

      Button('编辑')
        .fontSize(12)
        .fontColor(this.col().text)
        .backgroundColor(Color.Transparent)
        .type(ButtonType.Capsule)
        .height(28)
        .padding({ left: 8, right: 8 })
        .focusable(false)
        .bindMenu(this.buildEditMenu)

      Button('查看')
        .fontSize(12)
        .fontColor(this.col().text)
        .backgroundColor(Color.Transparent)
        .type(ButtonType.Capsule)
        .height(28)
        .padding({ left: 8, right: 8 })
        .focusable(false)
        .bindMenu(this.buildViewMenu)

      Button('工具')
        .fontSize(12)
        .fontColor(this.col().text)
        .backgroundColor(Color.Transparent)
        .type(ButtonType.Capsule)
        .height(28)
        .padding({ left: 8, right: 8 })
        .focusable(false)
        .bindMenu(this.buildToolsMenu)

      Button('帮助')
        .fontSize(12)
        .fontColor(this.col().text)
        .backgroundColor(Color.Transparent)
        .type(ButtonType.Capsule)
        .height(28)
        .padding({ left: 8, right: 8 })
        .focusable(false)
        .bindMenu(this.buildHelpMenu)

      Blank()

      this.buildToolButton('查找', () => { this.onFindReplace(); }, this.showFindDialog)
    }
    .width('100%')
    .height(32)
    .backgroundColor(this.col().surface)
    .border({ width: { bottom: 1 }, color: this.col().border })
    .animation({ duration: 100, curve: Curve.Linear })
    .padding({ left: 4, right: 4 })
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 工具栏胶囊按钮。
   * @param label   按钮文字
   * @param action  点击回调
   * @param active  是否处于激活态（高亮背景）
   */
  @Builder
  buildToolButton(label: string, action: () => void, active: boolean = false) {
    Button(label, { type: ButtonType.Capsule })
      .fontSize(12)
      .fontColor(this.col().textSecondary)
      .height(28)
      .padding({ left: 8, right: 8 })
      .backgroundColor(active ? this.col().activeBg : Color.Transparent)
      .focusable(false)
      .animation({ duration: 150, curve: Curve.Smooth })
      .onClick((): void => { action(); })
  }

  // ==================== 状态栏构建器 ====================

  @Builder
  buildStatusBar() {
    StatusBar({
      fileType: this.fileType,
      fileEncoding: this.fileEncoding,
      eolDisplay: this.eolDisplay(),
      insertMode: this.insertMode,
      totalLines: this.totalLines,
      totalChars: this.totalChars,
      cursorLine: this.cursorLine,
      cursorColumn: this.cursorColumn,
      cursorPulse: this.cursorPulse,
      selectionStats: this.selectionStats,
      indentType: AppStorage.get<string>('indentType') || '空格:4',
      langMenuBuilder: this.buildLangMenu,
      encodingMenuBuilder: this.buildEncodingMenu,
      onEolClick: (): void => { this.toggleEOL(); },
      onInsertModeClick: (): void => { this.insertMode = !this.insertMode; },
      onCursorClick: (): void => { this.showGoToLine = true; }
    })
  }
}