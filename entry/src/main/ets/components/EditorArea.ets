import { Highlighter, Token, TokenType } from '../service/Highlighter';
import { ProgrammingLanguage } from '../model/TabModel';
import { ThemeColors } from '../utils/ThemeColors';

interface TokenRender {
  text: string;
  tokenType: TokenType;
  startIndex: number;
  endIndex: number;
}

interface FoldLineIndicator {
  lineNumber: number;
  isFoldStart: boolean;
  isFoldEnd: boolean;
  isCollapsed: boolean;
  isHidden: boolean;
  indentLevel: number;
}

interface DiffRange {
  start: number;
  inserted: string;
  deleted: string;
  }

/**
 * 折叠区域数据类。
 * 表示一对 { } 之间的可折叠代码块。
 */
class FoldRegion {
  startLine: number;
  endLine: number;
  collapsed: boolean;
  hiddenText: string = '';

  constructor(startLine: number, endLine: number, collapsed: boolean = false) {
    this.startLine = startLine;
    this.endLine = endLine;
    this.collapsed = collapsed;
  }
}

class CommandItem {
  label: string;
  desc: string;
  key: string;
  constructor(label: string, desc: string, key: string) {
    this.label = label;
    this.desc = desc;
    this.key = key;
  }
}

class SymbolItem {
  label: string;
  line: number;
  kind: string;
  constructor(label: string, line: number, kind: string) {
    this.label = label;
    this.line = line;
    this.kind = kind;
  }
}

@Component
export struct EditorAreaImpl {
  @Prop @Watch('syncFromExternal') content: string = '';
  @Prop @Watch('onLanguagePropChange') language: string = 'plaintext';
  @Prop findPosition: number = -1;
  @Prop searchMatches: number[] = [];
  @Prop currentSearchIdx: number = -1;
  @Prop searchLen: number = 0;
  @Prop @Watch('onFoldAllChange') foldAll: boolean = false;
  @StorageProp('foldAll') storeFoldAll: boolean = false;
  @Prop isModified: boolean = false;
  @Prop readOnly: boolean = false;
  @Prop tabId: string = '';
  onContentChange?: (text: string) => void;
  onCursorMove?: (line: number, column: number) => void;
  onLanguageDetect?: (lang: string) => void;
  onSave?: () => void;
  onFindReplace?: () => void;
  onGoToLine?: () => void;
  onUndo?: () => void;
  onRedo?: () => void;
  onDuplicateLine?: () => void;
  onDeleteLine?: () => void;
  onMoveLineUp?: () => void;
  onMoveLineDown?: () => void;

  @StorageProp('fontSize') fontSize: number = 16;
  @StorageProp('tabSize') tabSize: number = 4;
  @StorageProp('currentColorMode') currentColorMode: string = 'light';
  @StorageProp('wordWrap') wordWrap: boolean = false;
  @StorageProp('showLineNumbers') showLineNumbers: boolean = true;

  @State editorText: string = '';
  @State tokens: Token[] = [];
  @State renderTokens: TokenRender[] = [];
  @State foldIndicators: FoldLineIndicator[] = [];
  private flashedFoldLine: number = -1;
  @State lineNumberText: string = '';
  @State flashActive: boolean = false;
  @State bracketPair: number[] = [];
  private wordHighlightPositions: number[] = [];
  private wordHighlightLen: number = 0;
  @State currentLineNum: number = 0;
  @State selectionStart: number = 0;
  @State selectionEnd: number = 0;

  private syncStats(): void {
    if (this.onContentChange) this.onContentChange(this.editorText);
  }
  private syncCursorStats(): void {
    if (this.onCursorMove) {
      const ln = this.currentLineNum + 1;
      let col = 1;
      if (this.trackedCursor >= 0 && this.editorText.length > 0) {
        for (let j = this.trackedCursor - 1; j >= 0 && this.editorText.charAt(j) !== '\n'; j--) {
          col++;
        }
      }
      this.onCursorMove(ln, col);
    }
  }

  private syncCurrentLineRange(): void {
    const lines = this.getLines();
    let pos = 0;
    for (let li = 0; li < this.currentLineNum && li < lines.length; li++) {
      pos += lines[li].length + 1;
    }
    this.currentLineStart = pos;
    this.currentLineEnd = pos +
      (this.currentLineNum < lines.length ? lines[this.currentLineNum].length : 0);
    this.syncCursorStats();
    this.buildRenderTokens();
  }

  private updateSelectionStats(oldText: string, newText: string): void {
    if (oldText.length > newText.length && oldText.length - newText.length > 1) {
      let i = 0;
      while (i < newText.length && oldText.charAt(i) === newText.charAt(i)) i++;
      const delLen = oldText.length - newText.length;
      const deleted = oldText.substring(i, i + delLen);
      const selLines = Math.max(1, deleted.split('\n').length);
      AppStorage.setOrCreate('selectionStats', '已选: ' + selLines + ' 行 ' + deleted.length + ' 字');
    }
    // 不主动清除，让状态栏持续显示上次选择统计
  }
  @State showShortcutsPanel: boolean = false;
  @State displayText: string = '';

  private fullText: string = '';
  private activeFoldCount: number = 0;
  private visibleLineCount: number = 1;
  private lastScrollY: number = 0;
  private editorScroller: Scroller = new Scroller();
  private foldRegions: FoldRegion[] = [];
  private textAreaController: TextAreaController = new TextAreaController();
  @State showMinimap: boolean = true;
  private minimapScroller: Scroller = new Scroller();
  private minimapScrollRatio: number = 0;

  private onEditorScroll(_xOffset: number, yOffset: number): void {
    const totalH = this.getLines().length * this.lineH();
    const viewH = this.visibleLineCount * this.lineH();
    if (totalH > 0 && viewH > 0) {
      this.minimapScrollRatio = Math.min(1, yOffset / Math.max(1, totalH - viewH));
    }
  }

  private minimapSliderHeight(): number {
    const total = this.getLines().length;
    if (total <= 1) return 100;
    const ratio = Math.min(1, this.visibleLineCount / total);
    return Math.max(6, ratio * 100);
  }

  private minimapSliderOffset(): number {
    const total = this.getLines().length;
    if (total <= 1) return 0;
    const sliderH = this.minimapSliderHeight();
    return this.minimapScrollRatio * (100 - sliderH);
  }

  @State showCommandPalette: boolean = false;
  @State showSymbolPalette: boolean = false;
  private cmdFilter: string = '';
  private static readonly COMMANDS: CommandItem[] = [
    new CommandItem('保存文件', '保存当前文件', 'Ctrl+S'),
    new CommandItem('撤销', '撤销上次编辑', 'Ctrl+Z'),
    new CommandItem('重做', '重做已撤销的编辑', 'Ctrl+Y'),
    new CommandItem('查找替换', '打开查找替换栏', 'Ctrl+F'),
    new CommandItem('转到行', '跳转到指定行号', 'Ctrl+G'),
    new CommandItem('全部折叠', '折叠所有代码块', ''),
    new CommandItem('展开全部', '展开所有折叠', ''),
    new CommandItem('切换行号', '显示/隐藏行号', ''),
    new CommandItem('切换自动换行', '开启/关闭自动换行', ''),
    new CommandItem('切换注释', '行注释切换', 'Ctrl+/'),
    new CommandItem('复制当前行', '复制光标所在行', 'Ctrl+D'),
    new CommandItem('删除当前行', '删除光标所在行', 'Ctrl+Shift+K'),
    new CommandItem('上移当前行', '当前行向上移动', 'Ctrl+Shift+↑'),
    new CommandItem('下移当前行', '当前行向下移动', 'Ctrl+Shift+↓'),
    new CommandItem('放大字体', '增大编辑器字号', 'Ctrl+='),
    new CommandItem('缩小字体', '减小编辑器字号', 'Ctrl+-'),
    new CommandItem('重置缩放', '恢复默认字号', 'Ctrl+0'),
    new CommandItem('插入日期时间', '插入当前日期时间', ''),
    new CommandItem('快捷键参考', '显示所有快捷键', 'F1'),
    new CommandItem('选中整行', '选中光标所在整行', 'Ctrl+L'),
    new CommandItem('跳转匹配括号', '跳转到匹配的括号', 'Ctrl+['),
    new CommandItem('复制行到下方', '向下插入空行', 'Ctrl+Enter'),
    new CommandItem('复制行到上方', '向上插入空行', 'Ctrl+Shift+Enter'),
  ];
  private getCommandPaletteItems(): CommandItem[] {
    const f = this.cmdFilter.toLowerCase();
    if (f.length === 0) {
      return EditorAreaImpl.COMMANDS;
    }
    return EditorAreaImpl.COMMANDS.filter((c): boolean =>
      c.label.toLowerCase().includes(f) || c.desc.toLowerCase().includes(f)
    );
  }

  // ===== 符号导航（Ctrl+Shift+O）=====
  private getSymbolItems(): SymbolItem[] {
    const items: SymbolItem[] = [];
    const lines = this.editorText.split('\n');
    const funcRe = new RegExp('\\b(def|class|function|void|int|bool|string|char|double|float|auto|long)\\s+(\\w+)\\s*\\(');
    const classRe = new RegExp('^\\s*(class|struct|enum|interface)\\s+(\\w+)');
    for (let i = 0; i < lines.length; i++) {
      const t = lines[i];
      let m: RegExpMatchArray | null = t.match(classRe);
      if (m) { items.push(new SymbolItem(m[2], i + 1, m[1])); continue; }
      m = t.match(funcRe);
      if (m) { items.push(new SymbolItem(m[2], i + 1, 'func')); }
    }
    const f = this.cmdFilter.toLowerCase();
    if (f.length === 0) return items;
    return items.filter((s: SymbolItem): boolean => s.label.toLowerCase().includes(f));
  }

  private goToSymbol(line: number): void {
    this.showSymbolPalette = false;
    this.cmdFilter = '';
    const lines = this.editorText.split('\n');
    let pos = 0;
    for (let i = 0; i < Math.min(line - 1, lines.length); i++) {
      pos += lines[i].length + 1;
    }
    this.trackedCursor = pos;
    this.currentLineNum = line - 1;
    this.textAreaController.caretPosition(pos);
  }

  private execCommand(label: string): void {
    this.showCommandPalette = false;
    this.cmdFilter = '';
    switch (label) {
      case '保存文件': if (this.onSave) this.onSave(); break;
      case '撤销': if (this.onUndo) this.onUndo(); break;
      case '重做': if (this.onRedo) this.onRedo(); break;
      case '查找替换': if (this.onFindReplace) this.onFindReplace(); break;
      case '转到行': if (this.onGoToLine) this.onGoToLine(); break;
      case '全部折叠': this.foldAllBlocks(); break;
      case '展开全部': this.unfoldAllBlocks(); break;
      case '切换行号': this.toggleLineNumbers(); break;
      case '切换自动换行': this.toggleWordWrap(); break;
      case '切换注释': this.toggleComment(); break;
      case '复制当前行': if (this.onDuplicateLine) this.onDuplicateLine(); break;
      case '删除当前行': if (this.onDeleteLine) this.onDeleteLine(); break;
      case '上移当前行': if (this.onMoveLineUp) this.onMoveLineUp(); break;
      case '下移当前行': if (this.onMoveLineDown) this.onMoveLineDown(); break;
      case '放大字体': this.zoomIn(); break;
      case '缩小字体': this.zoomOut(); break;
      case '重置缩放': this.zoomReset(); break;
      case '插入日期时间': this.insertDateTime(); break;
      case '快捷键参考': this.showShortcutsPanel = !this.showShortcutsPanel; break;
      case '选中整行': this.selectCurrentLine(); break;
      case '跳转匹配括号': this.jumpToMatchingBracket(); break;
      case '复制行到下方': this.insertLineBelow(); break;
      case '复制行到上方': this.insertLineAbove(); break;
    }
  }

  private foldAllBlocks(): void {
    AppStorage.setOrCreate('foldAll', true);
    this.foldAll = true;
    this.onFoldAllChange();
  }

  private unfoldAllBlocks(): void {
    AppStorage.setOrCreate('foldAll', false);
    this.foldAll = false;
    this.onFoldAllChange();
  }

  // ===== 代码片段（参考 VS Code Snippets）=====
  private static readonly SNIPPETS_CPP: Record<string, string> = {
    'fori': 'for (int i = 0; i < n; i++) {\n\t\n}',
    'fore': 'for (auto &x : v) {\n\t\n}',
    'if': 'if (condition) {\n\t\n}',
    'else': 'else {\n\t\n}',
    'main': 'int main() {\n\treturn 0;\n}',
    'class': 'class name {\npublic:\n\t\n};',
    'struct': 'struct name {\n\t\n};',
    'while': 'while (condition) {\n\t\n}',
    'switch': 'switch (x) {\ncase 1:\n\tbreak;\ndefault:\n\tbreak;\n}',
    'cout': 'std::cout <<  << std::endl;',
    'vector': 'std::vector<type> v;',
  };

  private static readonly SNIPPETS_PYTHON: Record<string, string> = {
    'def': 'def name():\n\t\n',
    'for': 'for x in iterable:\n\t\n',
    'if': 'if condition:\n\t\n',
    'class': 'class name:\n\t\n',
    'while': 'while condition:\n\t\n',
    'try': 'try:\n\t\nexcept:\n\t\n',
    'with': 'with open("file", "r") as f:\n\t\n',
  };

  private static readonly SNIPPETS_ARKTS: Record<string, string> = {
    'func': 'function name() {\n\t\n}',
    'for': 'for (let i = 0; i < n; i++) {\n\t\n}',
    'forof': 'for (const item of list) {\n\t\n}',
    'if': 'if (condition) {\n\t\n}',
    'else': 'else {\n\t\n}',
    'class': '@Observed\nclass name {\n\t\n}',
    'struct': '@Component\nstruct name {\n\tbuild() {\n\t}\n}',
    'switch': 'switch (x) {\n\tcase 1:\n\t\tbreak;\n\tdefault:\n\t\tbreak;\n}',
  };

  /**
   * Tab 键触发代码片段展开。
   * 读取光标前的单词，匹配到片段则替换。
   */
  private tryExpandSnippet(): boolean {
    const text = this.editorText;
    const pos = this.trackedCursor;
    if (pos <= 0) return false;
    // 提取光标前的单词
    let start = pos - 1;
    while (start >= 0) {
      const c = text.charCodeAt(start);
      if ((c >= 65 && c <= 90) || (c >= 97 && c <= 122)) { start--; } else { break; }
    }
    start++;
    const word = text.substring(start, pos);
    if (word.length === 0) return false;
    // 按语言选择片段表
    let snippets: Record<string, string> | undefined;
    if (this.language === 'cpp' || this.language === 'c') {
      snippets = EditorAreaImpl.SNIPPETS_CPP;
    } else if (this.language === 'python') {
      snippets = EditorAreaImpl.SNIPPETS_PYTHON;
    } else if (this.language === 'arkts' || this.language === 'typescript' || this.language === 'javascript') {
      snippets = EditorAreaImpl.SNIPPETS_ARKTS;
    }
    if (!snippets) return false;
    const expansion = snippets[word];
    if (!expansion) return false;
    // 替换并设置光标
    const before = text.substring(0, start);
    const after = text.substring(pos);
    const newText = before + expansion + after;
    this.editorText = newText;
    this.fullText = newText;
    // 光标放到展开后的第一行缩进位置
    const firstTab = expansion.indexOf('\t');
    const cursorPos = start + (firstTab >= 0 ? firstTab + 1 : expansion.length);
    this.trackedCursor = cursorPos;
    this.invalidateLines();
    this.updateTokens();
    this.buildLineList();
    this.textAreaController.caretPosition(cursorPos);
    return true;
  }

  private toggleLineNumbers(): void {
    const v = AppStorage.get('showLineNumbers') as boolean ?? true;
    AppStorage.setOrCreate('showLineNumbers', !v);
  }

  private toggleWordWrap(): void {
    const v = AppStorage.get('wordWrap') as boolean ?? false;
    AppStorage.setOrCreate('wordWrap', !v);
  }

  private zoomIn(): void {
    const fs = AppStorage.get('fontSize') as number ?? 16;
    AppStorage.setOrCreate('fontSize', Math.min(fs + 1, 48));
  }

  private zoomOut(): void {
    const fs = AppStorage.get('fontSize') as number ?? 16;
    AppStorage.setOrCreate('fontSize', Math.max(fs - 1, 8));
  }

  private zoomReset(): void {
    AppStorage.setOrCreate('fontSize', 16);
  }

  private insertDateTime(): void {
    const now = new Date();
    const s = now.getFullYear() + '-' +
      ('0' + (now.getMonth() + 1)).slice(-2) + '-' +
      ('0' + now.getDate()).slice(-2) + ' ' +
      ('0' + now.getHours()).slice(-2) + ':' +
      ('0' + now.getMinutes()).slice(-2);
    this.insertTextAtCursor(s);
  }

  private insertTextAtCursor(s: string): void {
    const pos = this.trackedCursor;
    const before = this.editorText.substring(0, pos);
    const after = this.editorText.substring(pos);
    const newText = before + s + after;
    this.editorText = newText;
    this.fullText = newText;
    this.trackedCursor = pos + s.length;
    this.invalidateLines();
    this.updateTokens();
    this.buildLineList();
    this.textAreaController.caretPosition(this.trackedCursor);
  }
  /**
   * 选中文本后输入括号 → 自动包裹选中内容。
   */
  private tryWrapSelection(oldText: string, newText: string): string | null {
    const pairs: Record<string, string> = { '(': ')', '[': ']', '{': '}', '\'': '\'', '"': '"' };
    let i = 0;
    while (i < oldText.length && i < newText.length && oldText.charAt(i) === newText.charAt(i)) i++;
    if (i >= newText.length) return null;
    const typed = newText.charAt(i);
    const close = pairs[typed];
    if (!close) return null;
    const delLen = oldText.length - newText.length + 1;
    const selected = oldText.substring(i, i + delLen);
    return newText.substring(0, i + 1) + selected + close + newText.substring(i + 1);
  }

  private autoIndentCaret: number = -1;
  private lastLang: string = 'plaintext';
  private bracketChars: string = '{}[]()<>';
  private bracketLevels: Map<number, number> = new Map();
  // 括号颜色调色板（6 色循环）
  private static readonly BRACKET_COLORS: string[] = [
    '#FFD700', '#DA70D6', '#00CED1', '#FF6B6B', '#87CEEB', '#FFA500'
  ];
  private bookmarkedLines: Set<number> = new Set();
  private cachedLines: string[] = [];
  private linesDirty: boolean = true;
  private useTabs: boolean = false;
  private indentSize: number = 4;

  /**
   * 缩进检测：扫描文本，推断使用 Tab 还是空格，以及缩进宽度。
   * 参考 VS Code indentationGuesser 算法。
   */
  private guessIndentation(text: string): void {
    const lines = text.split('\n');
    const maxLines = Math.min(lines.length, 10000);
    let spacesCount = 0;
    let tabsCount = 0;
    const diffs: number[] = new Array(9).fill(0); // diffs[1..8]

    let prevIndent = '';
    for (let i = 0; i < maxLines; i++) {
      const line = lines[i];
      // 跳过空行
      if (line.length === 0) {
        continue;
      }
      // 提取前导空白
      let ws = '';
      let hasTab = false;
      let hasSpace = false;
      for (let j = 0; j < line.length; j++) {
        const c = line.charAt(j);
        if (c === ' ') {
          ws += ' '; hasSpace = true;
        } else if (c === '\t') {
          ws += '\t'; hasTab = true;
        } else {
          break;
        }
      }
      // 纯空白行跳过
      if (ws.length === line.length) {
        continue;
      }
      if (hasTab) {
        tabsCount++;
      }
      if (!hasTab && ws.length >= 2) {
        spacesCount++;
      }
      // 计算与前行的缩进差
      if (prevIndent.length > 0 || ws.length > 0) {
        let diff = 0;
        let k = 0;
        const minLen = Math.min(prevIndent.length, ws.length);
        while (k < minLen && prevIndent.charAt(k) === ws.charAt(k)) {
          k++;
        }
        // 混合缩进（Tab+空格）忽略
        const tailA = prevIndent.substring(k);
        const tailB = ws.substring(k);
        let mixed = false;
        for (let t = 0; t < tailA.length; t++) {
          if (tailA.charAt(t) !== ' ') { mixed = true; break; }
        }
        for (let t = 0; t < tailB.length; t++) {
          if (tailB.charAt(t) !== ' ') { mixed = true; break; }
        }
        if (!mixed) {
          diff = Math.abs(tailA.length - tailB.length);
        }
        if (diff > 0 && diff <= 8) {
          diffs[diff]++;
        }
      }
      prevIndent = ws;
    }

    // 决定 Tab 还是空格
    this.useTabs = tabsCount > spacesCount;
    // 猜缩进宽度
    let best = 4;
    let bestScore = 0;
    const sizes = [2, 4, 6, 8, 3, 5, 7];
    for (const s of sizes) {
      if (diffs[s] > bestScore) {
        bestScore = diffs[s];
        best = s;
      }
    }
    // 2 特殊处理：若 2 的命中次数 ≥ 4 的 2/3，选 2
    if (best === 4 && diffs[2] >= diffs[4] * 2 / 3 && diffs[2] > 0) {
      best = 2;
    }
    this.indentSize = best > 0 ? best : 4;
    AppStorage.setOrCreate('indentType', this.useTabs ? ('Tab:' + this.indentSize) : ('空格:' + this.indentSize));
  }

  // ===== 单词导航 =====
  private static readonly WORD_SEP = new Set('`~!@#$%^&*()-=+[{]}\\|;:\'",.<>/?'.split(''));

  private wordClassOf(ch: string): number {
    if (ch === ' ' || ch === '\t') { return 1; }
    if (EditorAreaImpl.WORD_SEP.has(ch)) { return 2; }
    return 0;
  }

  private moveWordLeft(text: string, pos: number): number {
    if (pos <= 0) { return 0; }
    let i = pos - 1;
    while (i >= 0 && this.wordClassOf(text.charAt(i)) === 1) { i--; }
    if (i < 0) { return 0; }
    const cls = this.wordClassOf(text.charAt(i));
    while (i >= 0 && this.wordClassOf(text.charAt(i)) === cls) { i--; }
    return i + 1;
  }

  private moveWordRight(text: string, pos: number): number {
    if (pos >= text.length) { return text.length; }
    let i = pos;
    while (i < text.length && this.wordClassOf(text.charAt(i)) === 1) { i++; }
    if (i >= text.length) { return text.length; }
    const cls = this.wordClassOf(text.charAt(i));
    while (i < text.length && this.wordClassOf(text.charAt(i)) === cls) { i++; }
    return i;
  }

  private currentLineStart: number = 0;
  private currentLineEnd: number = 0;
  private trackedCursor: number = 0;

  private col(): ThemeColors { return ThemeColors.forMode(this.currentColorMode); }
  /**
   * 生成缩进字符串（tabSize 个空格）。
   */
  private getIndentStr(): string {
    if (this.useTabs) {
      return '\t';
    }
    let s = '';
    for (let i = 0; i < this.indentSize; i++) {
      s += ' ';
    }
    return s;
  }

  /**
   * 将文本偏移量转换为行号（0-based）。
   */
  private lineFromPos(text: string, pos: number): number {
    let line = 0;
    for (let i = 0; i < pos && i < text.length; i++) {
      if (text.charAt(i) === '\n') {
        line++;
      }
    }
    return line;
  }

  private columnFromPos(text: string, pos: number): number {
    let col = 0;
    for (let j = pos - 1; j >= 0 && text.charAt(j) !== '\n'; j--) { col++; }
    return col;
  }

  /**
   * 获取行数组，带脏标记缓存。
   * 首次调用或调用 invalidateLines() 后重新拆分，
   * 后续调用直接返回缓存数组，避免重复 split('\n')。
   */
  private getLines(): string[] {
    if (this.linesDirty) {
      this.cachedLines = this.fullText.split('\n');
      if (this.cachedLines.length === 0) {
        this.cachedLines.push('');
      }
      this.linesDirty = false;
    }
    return this.cachedLines;
  }
  private invalidateLines(): void { this.linesDirty = true; }
  private lineH(): number { return this.fontSize * 1.5; }

  // ================================================================
  // 括号匹配
  // ================================================================

  /**
   * 获取括号的配对字符。
   *   { → }   [ → ]   ( → )   " → "   ' → '   ` → `
   */
  private getPair(ch: string): string {
    switch (ch) {
      case '{': return '}';
      case '[': return ']';
      case '(': return ')';
      case '"': return '"';
      case "'": return "'";
      case '`': return '`';
      default:  return '';
    }
  }

  /**
   * 在文本中查找与 pos 处括号匹配的括号位置。
   * 支持 { } [ ] ( ) 三对括号，考虑嵌套深度。
   * 返回匹配括号的索引，未找到返回 -1。
   */
  private findMatchingBracket(text: string, pos: number): number {
    if (pos < 0 || pos >= text.length) {
      return -1;
    }
    const ch = text.charAt(pos);
    const idx = this.bracketChars.indexOf(ch);
    if (idx === -1) {
      return -1;
    }
    // idx 偶数 → 开括号，奇数 → 闭括号
    const isOpen = idx % 2 === 0;
    const pair = isOpen
      ? this.bracketChars[idx + 1]
      : this.bracketChars[idx - 1];
    let depth = 1;
    if (isOpen) {
      // 向后搜索匹配的闭括号
      for (let i = pos + 1; i < text.length; i++) {
        if (text.charAt(i) === ch) {
          depth++;
        } else if (text.charAt(i) === pair) {
          depth--;
          if (depth === 0) {
            return i;
          }
        }
      }
    } else {
      // 向前搜索匹配的开括号
      for (let i = pos - 1; i >= 0; i--) {
        if (text.charAt(i) === ch) {
          depth++;
        } else if (text.charAt(i) === pair) {
          depth--;
          if (depth === 0) {
            return i;
          }
        }
      }
    }
    return -1;
  }

  /**
   * 跟踪光标附近的括号并更新高亮配对。
   * 优先检查光标位置，其次检查光标前一个字符。
   */
  private updateBracketMatching(text: string, pos: number): void {
    for (let offset = 0; offset <= 1; offset++) {
      const cp = pos - offset;
      if (cp >= 0 && cp < text.length) {
        const ch = text.charAt(cp);
        if (this.bracketChars.indexOf(ch) !== -1) {
          const pair = this.findMatchingBracket(text, cp);
          if (pair >= 0) {
            this.bracketPair = cp < pair ? [cp, pair] : [pair, cp];
            return;
          }
        }
      }
    }
    this.bracketPair = [];
  }

  // Ctrl+E: 跳转到匹配括号
  private jumpToMatchingBracket(): void {
    if (this.bracketPair.length !== 2) return;
    let cursor = this.trackedCursor;
    const text = this.editorText;
    if (cursor < 0 || cursor > text.length) cursor = text.length;
    let target = this.bracketPair[0];
    // 判断光标更靠近哪个括号
    if (cursor >= this.bracketPair[0] - 1 &&
        cursor <= this.bracketPair[0] + 1) {
      target = this.bracketPair[1];
    } else if (cursor >= this.bracketPair[1] - 1 &&
               cursor <= this.bracketPair[1] + 1) {
      target = this.bracketPair[0];
    } else {
      target = this.bracketPair[1]; // 不在括号上 → 跳到闭合括号
    }
    this.textAreaController.caretPosition(target + 1);
    this.flashActive = true;
    setTimeout(() => { this.flashActive = false; }, 300);
  }

  // Ctrl+L: 选中当前行（跳到行首 + 全选效果 - 用括号高亮模拟）
  private selectCurrentLine(): void {
    const text = this.editorText; let cursor = this.trackedCursor;
    if (cursor < 0 || cursor > text.length) cursor = text.length;
    const line = this.lineFromPos(text, Math.min(cursor, text.length));
    const lines = this.getLines(); let lineStart = 0;
    for (let i = 0; i < line && i < lines.length; i++) lineStart += lines[i].length + 1;
    this.textAreaController.caretPosition(lineStart);
    this.flashActive = true; setTimeout(() => { this.flashActive = false; }, 300);
  }

  // ---------- 缩进辅助 ----------

  /**
   * 获取字符串开头的空白字符（前导空格/制表符）。
   */
  private getLeadingWs(s: string): string {
    let len = 0;
    while (len < s.length) {
      const c = s.charCodeAt(len);
      if (c === 32 || c === 9) {
        len++;
      } else {
        break;
      }
    }
    return s.substring(0, len);
  }

  /**
   * 去除字符串末尾的空白字符。
   */
  private trimTrailingWs(s: string): string {
    let end = s.length;
    while (end > 0) {
      const c = s.charCodeAt(end - 1);
      if (c === 32 || c === 9) {
        end--;
      } else {
        break;
      }
    }
    return s.substring(0, end);
  }

  /**
   * 获取当前行的缩进宽度（前导空白字符数）。
   */
  private getLineIndent(line: string): number {
    let n = 0;
    while (n < line.length) {
      const ch = line.charAt(n);
      if (ch === ' ' || ch === '\t') {
        n++;
      } else {
        break;
      }
    }
    return n;
  }

  private indentAtCursor(): void {
    const text = this.editorText; const insert = this.getIndentStr();
    let cursor = this.trackedCursor;
    if (cursor < 0 || cursor > text.length) cursor = text.length;
    const t = text.substring(0, cursor) + insert + text.substring(cursor);
    this.editorText = t;
    this.fullText = t;
    this.invalidateLines();
    this.updateTokens();
    this.buildLineList();
    if (this.onContentChange) this.onContentChange(t);
    setTimeout(() => { this.textAreaController.caretPosition(cursor + insert.length); }, 0);
  }

  private outdentLine(): void {
    const text = this.editorText; const lines = this.getLines();
    let cursor = this.trackedCursor;
    if (cursor < 0 || cursor > text.length) cursor = text.length;
    const line = this.lineFromPos(text, Math.min(cursor, text.length));
    if (line >= lines.length) return;
    const ws = this.getLeadingWs(lines[line]); const remove = Math.min(ws.length, this.tabSize);
    if (remove === 0) return;
    lines[line] = lines[line].substring(remove);
    const t = lines.join('\n');
    this.editorText = t;
    this.fullText = t;
    this.invalidateLines();
    this.updateTokens();
    this.buildLineList();
    if (this.onContentChange) this.onContentChange(t);
    setTimeout(() => { this.textAreaController.caretPosition(Math.max(0, cursor - remove)); }, 0);
  }

  // Ctrl+Enter / Ctrl+Shift+Enter: 插入空行
  private insertLineBelow(): void {
    const text = this.editorText; let cursor = this.trackedCursor;
    if (cursor < 0 || cursor > text.length) cursor = text.length;
    const eol = text.indexOf('\n', cursor); const insPos = eol >= 0 ? eol + 1 : text.length;
    const line = this.lineFromPos(text, Math.min(cursor, text.length));
    const lines = this.getLines();
    const indent = line < lines.length ? this.getLeadingWs(lines[line]) : '';
    const t = text.substring(0, insPos) + '\n' + indent + text.substring(insPos);
    this.editorText = t;
    this.fullText = t;
    this.invalidateLines();
    this.updateTokens();
    this.buildLineList();
    if (this.onContentChange) this.onContentChange(t);
    setTimeout(() => { this.textAreaController.caretPosition(insPos + 1 + indent.length); }, 0);
  }

  private insertLineAbove(): void {
    const text = this.editorText; let cursor = this.trackedCursor;
    if (cursor < 0 || cursor > text.length) cursor = text.length;
    const sol = text.lastIndexOf('\n', cursor - 1); const insPos = sol >= 0 ? sol + 1 : 0;
    const line = this.lineFromPos(text, Math.min(cursor, text.length));
    const lines = this.getLines();
    const indent = line < lines.length ? this.getLeadingWs(lines[line]) : '';
    const t = text.substring(0, insPos) + indent + '\n' + text.substring(insPos);
    this.editorText = t;
    this.fullText = t;
    this.invalidateLines();
    this.updateTokens();
    this.buildLineList();
    if (this.onContentChange) this.onContentChange(t);
    setTimeout(() => { this.textAreaController.caretPosition(insPos + indent.length); }, 0);
  }

  // ---------- CRLF ----------

  /**
   * 统一换行符：\r\n 和 \r → \n。
   */
  private replaceCrlf(s: string): string {
    let out = '';
    let idx = 0;
    while (idx < s.length) {
      const c = s.charCodeAt(idx);
      if (c === 13) {
        // \r → \n，如果后跟 \n 则跳过
        out += '\n';
        if (idx + 1 < s.length && s.charCodeAt(idx + 1) === 10) {
          idx++;
        }
        idx++;
      } else {
        out += s.charAt(idx);
        idx++;
      }
    }
    return out;
  }

  // ---------- diff 辅助 ----------

  /**
   * 计算两个文本的最小差异范围。
   * 返回被删除的旧文本、插入的新文本、以及变更起始位置。
   */
  private diffRange(oldText: string, newText: string): DiffRange {
    let start = 0;
    let endOld = oldText.length - 1;
    let endNew = newText.length - 1;
    while (start <= endOld && start <= endNew &&
           oldText.charAt(start) === newText.charAt(start)) {
      start++;
    }
    while (endOld >= start && endNew >= start &&
           oldText.charAt(endOld) === newText.charAt(endNew)) {
      endOld--;
      endNew--;
    }
    return {
      start: start,
      inserted: newText.substring(start, endNew + 1),
      deleted: oldText.substring(start, endOld + 1)
    };
  }

  // ---------- 闭合括号去重（IME 兼容） ----------

  private fixCloseDuplicates(text: string): string {
    const cs = ')}]';
    for (let i = 0; i < text.length - 1; i++) {
      if (cs.indexOf(text.charAt(i)) >= 0 && text.charAt(i + 1) === text.charAt(i)) {
        this.autoIndentCaret = i + 1;
        return text.substring(0, i) + text.substring(i + 1);
      }
    }
    return text;
  }

  // ---------- 选区包裹 ----------

  private trySelectionWrap(oldText: string, newText: string): string {
    if (newText.length >= oldText.length) {
      return newText;
    }
    const d = this.diffRange(oldText, newText);
    if (d.deleted.length < 1 || d.inserted.length !== 1) {
      return newText;
    }
    const ch = d.inserted.charAt(0);
    const close = this.getPair(ch);
    if (!close || ')}]'.indexOf(ch) >= 0) {
      return newText;
    }
    this.autoIndentCaret = d.start + d.deleted.length + 2;
    return oldText.substring(0, d.start) +
      ch + d.deleted + close +
      oldText.substring(d.start + d.deleted.length);
  }

  // ---------- 单字符自动闭合 ----------

  private tryAutoClose(oldText: string, newText: string): string {
    if (newText.length !== oldText.length + 1) return newText;
    const d = this.diffRange(oldText, newText);
    if (d.inserted.length !== 1 || d.deleted.length !== 0) return newText;
    const ch = d.inserted.charAt(0);
    if (')}]'.indexOf(ch) >= 0) return newText;
    const close = this.getPair(ch); if (!close) return newText;
    const nextCh = oldText.length > d.start ? oldText.charAt(d.start) : '';
    if (nextCh === close) return newText;
    // 引号在字符串内不自动闭合
    if (close === ch) {
      const lineBefore = oldText.substring(0, d.start)
        .split('\n').pop() || '';
      let count = 0;
      for (let i = 0; i < lineBefore.length; i++) {
        if (lineBefore.charAt(i) === ch) {
          count++;
        }
      }
      if (count % 2 === 1) {
        return newText; // 奇数个引号 → 光标在字符串内
      }
    }
    this.autoIndentCaret = d.start + 1;
    return newText.substring(0, d.start + 1) + close + newText.substring(d.start + 1);
  }

  // ---------- 智能退格 ----------

  private trySmartBackspace(oldText: string, newText: string): string {
    if (newText.length !== oldText.length - 1) return newText;
    const d = this.diffRange(oldText, newText);
    if (d.inserted.length !== 0 || d.deleted.length !== 1) return newText;
    const ch = d.deleted.charAt(0);
    const close = this.getPair(ch);
    if (!close) {
      return newText;
    }
    // 引号配对检查
    if (close === ch) {
      const lineBefore = oldText.substring(0, d.start)
        .split('\n').pop() || '';
      let count = 0;
      for (let i = 0; i < lineBefore.length; i++) {
        if (lineBefore.charAt(i) === ch) {
          count++;
        }
      }
      if (count % 2 === 1) {
        return newText;
      }
    }
    if (d.start < oldText.length - 1 && oldText.charAt(d.start + 1) === close) {
      this.autoIndentCaret = d.start;
      return newText.substring(0, d.start) + newText.substring(d.start + 1);
    }
    // 智能退格：在缩进空白位置按退格 → 回退一整级缩进
    if (d.deleted === ' ' || d.deleted === '\t') {
      const line = oldText.substring(0, d.start).split('\n').pop() || '';
      // 确保光标前全是空白
      let allWs = true;
      for (let i = 0; i < line.length; i++) {
        if (line.charAt(i) !== ' ' && line.charAt(i) !== '\t') { allWs = false; break; }
      }
      if (allWs && line.length > 0) {
        const indent = this.getIndentStr();
        const remove = line.length % indent.length === 0 ? indent.length : line.length % indent.length;
        if (remove > 0 && remove <= line.length) {
          this.autoIndentCaret = d.start - remove;
          const cutStart = d.start - line.length;
          if (cutStart < 0) return newText;
          return oldText.substring(0, cutStart) + line.substring(remove) + oldText.substring(d.start + 1);
        }
      }
    }
    return newText;
  }

  // ---------- 回车缩进 ----------

  /**
   * 回车时自动缩进。
   * 根据上一行的缩进和行尾字符决定下一行的缩进级别：
   *   - 行尾是 { → 缩进 + 1 级，并自动补 }
   *   - 行尾是 ( → 缩进 + 1 级
   *   - 行首是 })] → 对齐到上一行并减少缩进
   *   - 上一行是 // 注释 → 保持缩进并补 //
   */
  private tryAutoIndent(oldText: string, newText: string): string {
    if (newText.length !== oldText.length + 1) {
      return newText;
    }
    // 找到变更位置（即刚输入的回车符位置）
    let i = 0;
    while (i < oldText.length &&
           oldText.charAt(i) === newText.charAt(i)) {
      i++;
    }
    if (newText.charAt(i) !== '\n') {
      return newText;
    }
    // 修正：当光标位于原有 \n 上按回车时，前缀扫描会越过实际插入点
    // 例如 oldText="...;\n}", newText="...;\n\n}"  → i 指到了 } 的位置
    // 检测 newText[i-1..i] 是否形成双 \n，是则回退
    if (i > 0 && newText.charAt(i - 1) === '\n') {
      i = i - 1;
    }
    // 上一行的缩进和内容
    const before = oldText.substring(0, i);
    // 跳过可能的尾部 \n（当光标在行首时 before 以 \n 结尾）
    const nlIdx = before.lastIndexOf('\n', before.length - 2);
    const lastLineStart = nlIdx >= 0 ? nlIdx + 1 : 0;
    const prevLine = before.substring(lastLineStart);
    const indent = this.getLeadingWs(prevLine);
    const trimmed = this.trimTrailingWs(prevLine);
    const ac = newText.substring(i + 1);

    // 行尾是 { → 增加缩进，补 }，光标放在中间
    if (trimmed.endsWith('{')) {
      const extra = this.getIndentStr();
      const cb = '\n' + indent + '}';
      if (ac.length > 0 && ac.charAt(0) === '}') {
        this.autoIndentCaret = i + 1 + indent.length + extra.length;
        return newText.substring(0, i + 1) +
          indent + extra + cb + ac.substring(1);
      }
      this.autoIndentCaret = i + 1 + indent.length + extra.length;
      return newText.substring(0, i + 1) +
        indent + extra + cb + ac;
    }
    // 行尾是 ( → 增加缩进
    if (trimmed.endsWith('(')) {
      const extra = this.getIndentStr();
      this.autoIndentCaret = i + 1 + indent.length + extra.length;
      return newText.substring(0, i + 1) +
        indent + extra + newText.substring(i + 1);
    }
    // 行首是 })] → 对齐并减少缩进
    if (ac.length > 0 && ')}]'.indexOf(ac.charAt(0)) >= 0) {
      this.autoIndentCaret = i + 2;
      return before + ac.charAt(0) + '\n' + ac.substring(1);
    }
    // 上一行是 // 注释 → 保持缩进并补 //
    if (trimmed.startsWith('//') && trimmed.length > 2) {
      this.autoIndentCaret = i + 1 + indent.length + 2;
      return newText.substring(0, i + 1) +
        indent + '// ' + newText.substring(i + 1);
    }
    if (trimmed === '//') {
      this.autoIndentCaret = i + 1 + indent.length;
      return newText.substring(0, i + 1) +
        indent + newText.substring(i + 1);
    }
    // 默认：保持上一行的缩进
    this.autoIndentCaret = i + 1 + indent.length;
    return newText.substring(0, i + 1) +
      indent + newText.substring(i + 1);
  }

  // ---------- } 自动对齐缩进 ----------

  /**
   * 检测到用户输入 } 且 } 在行首（前面只有空白）时，
   * 自动将 } 的缩进对齐到匹配的 { 的缩进级别。
   */
  private tryBraceIndent(oldText: string, newText: string): string {
    if (newText.length !== oldText.length + 1) {
      return newText;
    }
    const d = this.diffRange(oldText, newText);
    if (d.inserted.length !== 1) {
      return newText;
    }
    const closeCh = d.inserted.charAt(0);
    if (')]}'.indexOf(closeCh) < 0) {
      return newText;
    }
    const insPos = d.start;
    // 检测闭合括号是否在行首（前面只有空白）
    const sol = oldText.lastIndexOf('\n', insPos - 1);
    const lineStart = sol >= 0 ? sol + 1 : 0;
    for (let p = lineStart; p < insPos; p++) {
      const c = oldText.charAt(p);
      if (c !== ' ' && c !== '\t' && c !== '\n') {
        return newText; // 行中有非空白字符，不处理
      }
    }
    // 找到匹配的开括号的缩进
    const after = newText.substring(insPos + 1);
    const matchPos = this.findMatchingBracket(newText, insPos);
    if (matchPos < 0) {
      return newText;
    }
    const matchLine = newText.substring(0, matchPos).split('\n');
    const openLine = matchLine[matchLine.length - 1];
    const openIndent = this.getLeadingWs(openLine);
    // 替换闭合括号前面的空白
    const result = newText.substring(0, lineStart) +
      openIndent + closeCh + after;
    this.autoIndentCaret = lineStart + openIndent.length + 1;
    return result;
  }

  /**
   * 粘贴多行文本后自动调整缩进。
   * 保留粘贴内容的相对缩进，只调整第一行的基础缩进以匹配当前上下文。
   */
  private autoIndentPaste(): void {
    const lines = this.editorText.split('\n');
    if (lines.length < 2) return;
    // 获取当前行的缩进
    const curLine = this.currentLineNum;
    if (curLine <= 0 || curLine >= lines.length) return;
    const curIndent = this.getLeadingWs(lines[curLine]);
    // 从当前位置往后查找粘贴的第一行（非空行）
    let pasteStart = curLine;
    while (pasteStart < lines.length && lines[pasteStart].length === 0) pasteStart++;
    if (pasteStart >= lines.length) return;
    const pasteIndent = this.getLeadingWs(lines[pasteStart]);
    // 如果缩进相同或粘贴行没缩进，不处理
    if (curIndent.length === pasteIndent.length) return;
    // 如果粘贴行的缩进是当前行缩进的前缀，不处理（可能是正确的）
    if (pasteIndent.startsWith(curIndent)) return;
    // 调整：把粘贴行的缩进替换为当前上下文的缩进
    const newLines = lines.slice();
    for (let i = pasteStart; i < lines.length; i++) {
      if (lines[i].length === 0) continue;
      const ws = this.getLeadingWs(lines[i]);
      if (ws.startsWith(pasteIndent)) {
        newLines[i] = curIndent + lines[i].substring(pasteIndent.length);
      }
    }
    const newText = newLines.join('\n');
    if (newText !== this.editorText) {
      this.editorText = newText;
      this.fullText = newText;
      this.invalidateLines();
      this.updateTokens();
      this.buildLineList();
    }
  }

  // ==================== CORE: handleTextChange ====================

  /**
   * 文本变更核心处理入口。
   * 流程：CRLF 清理 → IME 去重 → 选区包裹 → 自动闭合 →
   *       智能退格 → 回车缩进 → } 对齐 → 光标更新 → 重绘。
   */
  handleTextChange(value: string): void {
    if (this.readOnly) {
      return;
    }
    let cleanValue = this.replaceCrlf(value);
    if (cleanValue === this.editorText) {
      return;
    }
    this.autoIndentCaret = -1;

    // 选中文本后打字 → 括号自动包裹
    if (cleanValue.length < this.editorText.length) {
      const wrapped = this.tryWrapSelection(this.editorText, cleanValue);
      if (wrapped !== null) {
        cleanValue = wrapped;
      }
    }

    this.updateSelectionStats(this.editorText, cleanValue);

    if (cleanValue.length > this.editorText.length) {
      // 插入路径：重复括号修复 → 自动闭合 → 自动缩进 → } 对齐
      cleanValue = this.fixCloseDuplicates(cleanValue);
      if (cleanValue === this.editorText) {
        return;
      }
      cleanValue = this.tryAutoClose(this.editorText, cleanValue);
      cleanValue = this.tryAutoIndent(this.editorText, cleanValue);
      cleanValue = this.tryBraceIndent(this.editorText, cleanValue);

      // 计算光标位置
      const cursorExplicit = this.autoIndentCaret >= 0;
      let changedPos: number;
      if (cursorExplicit) {
        changedPos = this.autoIndentCaret;
        this.autoIndentCaret = -1;
      } else {
        changedPos = 0;
        const ol = this.editorText.length;
        while (changedPos < cleanValue.length &&
               changedPos < ol &&
               cleanValue.charAt(changedPos) ===
               this.editorText.charAt(changedPos)) {
          changedPos++;
        }
      }
      this.trackedCursor = changedPos;

      this.currentLineNum = this.lineFromPos(cleanValue, changedPos);
      this.updateBracketMatching(cleanValue, changedPos);
      this.updateWordHighlight();

      if (this.activeFoldCount === 0) {
        this.editorText = cleanValue;
        this.fullText = cleanValue;
        this.syncStats();
      } else {
        this.applyVisibleChange(cleanValue);
      }
      if (cursorExplicit) {
        this.textAreaController.caretPosition(changedPos);
        setTimeout(() => {
          this.textAreaController.caretPosition(changedPos);
          setTimeout(() => {
            this.textAreaController.caretPosition(changedPos);
          }, 50);
        }, 0);
      }
      this.displayText = this.editorText;
      this.invalidateLines();

      // 更新当前行范围
      const allLines = this.getLines();
      let linePos = 0;
      for (let li = 0; li < this.currentLineNum && li < allLines.length; li++) {
        linePos += allLines[li].length + 1;
      }
      this.currentLineStart = linePos;
      this.currentLineEnd = linePos +
        (this.currentLineNum < allLines.length
          ? allLines[this.currentLineNum].length : 0);

      // 自动检测语言
      if (this.language === 'plaintext' && cleanValue.length > 8) {
        const d = this.detectLanguage();
        if (d !== 'plaintext' && this.onLanguageDetect) {
          this.onLanguageDetect(d);
        }
      }

      this.updateTokens();
      this.buildLineList();
      this.buildRenderTokens();
      this.scrollToCurrentLine();
      if (this.onCursorMove) {
        const ln = this.currentLineNum + 1;
        let col = 1;
        for (let j = changedPos - 1; j >= 0; j--) {
          if (cleanValue.charAt(j) === '\n') {
            break;
          }
          col++;
        }
        this.onCursorMove(ln, col);
      }
    } else {
      // 删除路径：选区包裹 → 智能退格 → 状态同步 → 光标 → 重绘
      cleanValue = this.trySelectionWrap(this.editorText, cleanValue);
      cleanValue = this.trySmartBackspace(this.editorText, cleanValue);

      const cursorExplicit = this.autoIndentCaret >= 0;
      let changedPos: number;
      if (cursorExplicit) {
        changedPos = this.autoIndentCaret;
        this.autoIndentCaret = -1;
      } else {
        changedPos = 0;
        while (changedPos < cleanValue.length &&
               changedPos < this.editorText.length &&
               cleanValue.charAt(changedPos) ===
               this.editorText.charAt(changedPos)) {
          changedPos++;
        }
      }

      this.editorText = cleanValue;
      this.fullText = cleanValue;
      this.syncStats();
      if (cursorExplicit) {
        this.textAreaController.caretPosition(changedPos);
        setTimeout(() => {
          this.textAreaController.caretPosition(changedPos);
          setTimeout(() => {
            this.textAreaController.caretPosition(changedPos);
          }, 50);
        }, 0);
      }
      this.displayText = cleanValue;
      this.invalidateLines();

      this.trackedCursor = changedPos;
      this.currentLineNum = this.lineFromPos(cleanValue, changedPos);
      this.updateBracketMatching(cleanValue, changedPos);
      this.updateWordHighlight();

      this.updateTokens();
      this.buildLineList();
      this.buildRenderTokens();
      this.scrollToCurrentLine();
    }
  }

  private handleSelectionChange(selStart: number, selEnd: number): void {
    this.selectionStart = selStart;
    this.selectionEnd = selEnd;
    this.trackedCursor = selEnd;
    this.currentLineNum = this.lineFromPos(this.editorText, selEnd);
    this.syncCurrentLineRange();
    this.updateBracketMatching(this.editorText, selEnd);
    this.updateWordHighlight();
    this.buildRenderTokens();
    if (selStart === selEnd) {
      AppStorage.setOrCreate('selectionStats', '');
    } else {
      const selected = this.editorText.substring(selStart, selEnd);
      const selLines = selected.split('\n').length;
      AppStorage.setOrCreate('selectionStats', '已选: ' + selLines + ' 行 ' + selected.length + ' 字');
    }
  }

  /**
   * 将「可视文本」（折叠行被省略）的编辑应用到完整文本。
   * 通过映射可视化行号到真实行号来还原折叠内容。
   */
  private applyVisibleChange(newVisible: string): void {
    const ovl = this.editorText.split('\n');
    const nvl = newVisible.split('\n');
    const fl = this.getLines();
    // 收集所有被折叠隐藏的行号
    const cs = new Set<number>();
    for (const r of this.foldRegions) {
      if (r.collapsed) {
        for (let li = r.startLine + 1; li < r.endLine; li++) {
          cs.add(li);
        }
      }
    }
    // 构建 可视化索引 → 真实索引 映射
    const o2f: number[] = [];
    for (let vi = 0, fi = 0; vi < ovl.length; vi++, fi++) {
      while (cs.has(fi)) {
        fi++;
      }
      o2f.push(fi);
    }
    // 从两端缩小差异范围
    let de = ovl.length - 1;
    let dne = nvl.length - 1;
    while (de >= 0 && dne >= 0 && ovl[de] === nvl[dne]) {
      de--;
      dne--;
    }
    // 重构完整文本
    const r: string[] = [];
    for (let i = 0; i <= de; i++) {
      r.push(fl[o2f[i]]);
    }
    for (let i = 0; i <= dne; i++) {
      r.push(nvl[i]);
    }
    for (let i = de + 1; i < ovl.length; i++) {
      r.push(fl[o2f[i]]);
    }
    this.fullText = r.join('\n');
    this.editorText = newVisible;
  }

  // ---------- detect / tokens / render / lines ----------

  /**
   * 检测编程语言（基于文本内容的关键字匹配）。
   */
  private detectLanguage(): string {
    const t = this.fullText;
    if (t.length < 2) return 'plaintext';
    if (t.indexOf('@Component') >= 0 || t.indexOf('@Entry') >= 0 || t.indexOf('@Builder') >= 0) return 'arkts';
    if (t.indexOf('#include') >= 0) return 'cpp';
    if (t.indexOf('using namespace') >= 0) return 'cpp';
    if (t.indexOf('def ') >= 0 && t.indexOf('self') >= 0) return 'python';
    if (t.indexOf('import java.') >= 0 || t.indexOf('public class') >= 0) return 'java';
    if (t.indexOf('package main') >= 0 || t.indexOf('func main') >= 0) return 'go';
    if (t.indexOf('fn main') >= 0 || t.indexOf('let mut') >= 0) return 'rust';
    if (t.indexOf('<!DOCTYPE html') >= 0 || t.indexOf('<html') >= 0) return 'html';
    if (t.indexOf('<?xml') >= 0) return 'xml';
    if (t.indexOf('SELECT ') >= 0 && t.indexOf('FROM ') >= 0) return 'sql';
    if (t.indexOf('#!/bin/bash') >= 0 || t.indexOf('#!/bin/sh') >= 0) return 'shell';
    return 'plaintext';
  }

  /**
   * 重新生成语法高亮 Token。
   */
  private updateTokens(): void {
    if (this.language === 'plaintext') {
      this.tokens = [];
    } else {
      this.tokens = Highlighter.tokenize(
        this.fullText,
        this.language as ProgrammingLanguage
      );
    }
    this.computeBracketLevels();
    this.buildRenderTokens();
  }

  /**
   * 计算括号嵌套层级，用于分色显示。
   * 参考 VS Code bracket pair colorization。
   */
  private computeBracketLevels(): void {
    this.bracketLevels = new Map();
    // 每种括号类型的独立深度栈
    const depth: Map<string, number> = new Map();
    const full = this.fullText;
    const openBrackets = new Set('{(['.split(''));
    const closeBrackets = new Set('})]'.split(''));
    const closeToOpen: Record<string, string> = { '}': '{', ']': '[', ')': '(' };

    for (let i = 0; i < full.length; i++) {
      const ch = full.charAt(i);
      if (openBrackets.has(ch)) {
        const d = (depth.get(ch) || 0) + 1;
        depth.set(ch, d);
        this.bracketLevels.set(i, d);
      } else if (closeBrackets.has(ch)) {
        const open = closeToOpen[ch];
        if (open) {
          const d = depth.get(open) || 0;
          if (d > 0) {
            depth.set(open, d - 1);
          }
          this.bracketLevels.set(i, d);
        }
      }
    }
  }

  /**
   * 构建用于 UI 渲染的 Token 列表。
   * 跳过被折叠隐藏的文本区域，只保留可见 Token。
   */
  /**
   * 将 renderTokens 按换行拆分为每行数组，参考 VS Code 按行渲染方式。
   */
  private splitTokensByLine(): TokenRender[][] {
    const result: TokenRender[][] = [];
    let curLine: TokenRender[] = [];
    for (const tok of this.renderTokens) {
      if (tok.text.indexOf('\n') >= 0) {
        const parts = tok.text.split('\n');
        for (let i = 0; i < parts.length; i++) {
          if (parts[i].length > 0 || i < parts.length - 1) {
            curLine.push({
              text: parts[i],
              tokenType: tok.tokenType,
              startIndex: tok.startIndex,
              endIndex: tok.startIndex + parts[i].length
            });
          }
          if (i < parts.length - 1) {
            result.push(curLine);
            curLine = [];
          }
        }
      } else {
        curLine.push(tok);
      }
    }
    if (curLine.length > 0) {
      result.push(curLine);
    }
    return result;
  }

  private buildRenderTokens(): void {
    const result: TokenRender[] = [];
    let pos = 0;
    const cr: number[][] = [];
    const lines = this.getLines();

    // 计算每行的起始字符偏移
    const ls: number[] = [0];
    for (let i = 0; i < lines.length; i++) {
      if (i > 0) {
        ls.push(ls[i - 1] + lines[i - 1].length + 1);
      }
    }
    // 收集折叠区域的范围（字符偏移）
    // 折叠范围：从 opening line 末尾到 closing line 开头，保留 closing line（}）可见
    for (const r of this.foldRegions) {
      if (r.collapsed &&
          r.endLine > r.startLine &&
          r.startLine < ls.length &&
          r.endLine < lines.length) {
        cr.push([
          ls[r.startLine] + lines[r.startLine].length + 1,
          ls[r.endLine]  // closing line 及其 `}` 保持可见
        ]);
      }
    }
    // 过滤 Token：跳过折叠区域内的 Token
    for (const tok of this.tokens) {
      if (tok.text.length === 0) { pos += tok.text.length; continue; }
      let skip = false;
      for (const rr of cr) {
        if (pos >= rr[0] && pos + tok.text.length <= rr[1] + 1) {
          skip = true;
          break;
        }
      }
      if (!skip) {
        result.push({
          text: tok.text,
          tokenType: tok.type,
          startIndex: pos,
          endIndex: pos + tok.text.length
        });
      }
      pos += tok.text.length;
    }
    this.renderTokens = result;
  }

  /**
   * 构建行列表（行号文本 + 折叠指示器）。
   */
  private buildLineList(): void {
    const lines = this.getLines();
    this.findAllFoldRegions();

    // 如果 foldAll 激活，新出现的代码块也自动折叠（同时检测 prop 和 storage）
    if (this.foldAll || this.storeFoldAll) {
      for (const r of this.foldRegions) {
        r.collapsed = true;
      }
    }

    // 收集所有被折叠隐藏的行
    const cs = new Set<number>();
    for (const r of this.foldRegions) {
      if (r.collapsed) {
        for (let li = r.startLine + 1; li < r.endLine; li++) {
          cs.add(li);
        }
      }
    }
    this.activeFoldCount = cs.size;
    const parts: string[] = [];
    const inds: FoldLineIndicator[] = [];
    for (let i = 0; i < lines.length; i++) {
      // 所有行都显示，保证行号与 TextArea 对齐；折叠行仅加折叠标记
      parts.push((i + 1).toString());
      const ind: FoldLineIndicator = {
        lineNumber: i,
        isFoldStart: false,
        isFoldEnd: false,
        isCollapsed: false,
        isHidden: cs.has(i),
        indentLevel: this.getLineIndent(lines[i])
      };
      const r = this.findFoldRegionAtLine(i);
      if (r.startLine >= 0 && r.startLine === i) {
        ind.isFoldStart = true;
        ind.isCollapsed = r.collapsed;
      }
      if (r.startLine >= 0 && r.endLine === i) {
        ind.isFoldEnd = true;
      }
      inds.push(ind);
    }
    this.foldIndicators = inds;
    this.lineNumberText = parts.join('\n');
    this.visibleLineCount = parts.length > 0 ? parts.length : 1;
  }

  // ================================================================
  // 折叠 (Folding)
  // ================================================================

  /**
   * 扫描全文，找出所有可折叠的 { } 块。
   * 时间复杂度 O(n²) 最坏，但对于典型源码文件可接受。
   */
  private findAllFoldRegions(): void {
    // 保留旧折叠状态，避免每次重建时丢失
    const oldCollapsed = new Map<string, boolean>();
    for (const r of this.foldRegions) {
      oldCollapsed.set(r.startLine + ':' + r.endLine, r.collapsed);
    }
    this.foldRegions = [];
    const lines = this.getLines();
    for (let i = 0; i < lines.length; i++) {
      const trimmed = this.trimTrailingWs(lines[i]);
      if (!trimmed.endsWith('{')) {
        continue;
      }
      // 找到匹配的 }
      let depth = 1;
      for (let j = i + 1; j < lines.length; j++) {
        const tj = this.trimTrailingWs(lines[j]);
        if (tj.endsWith('{')) {
          depth++;
        }
        if (tj === '}' || tj.startsWith('}')) {
          depth--;
          if (depth === 0) {
            const key = i + ':' + j;
            const wasCollapsed = oldCollapsed.get(key) || false;
            this.foldRegions.push(new FoldRegion(i, j, wasCollapsed));
            break;
          }
        }
      }
    }
  }

  /**
   * 查找某行所属的折叠区域。
   * 若未找到则返回占位对象 (startLine = -1)。
   */
  private findFoldRegionAtLine(line: number): FoldRegion {
    for (let idx = this.foldRegions.length - 1; idx >= 0; idx--) {
      const r = this.foldRegions[idx];
      if (line >= r.startLine && line <= r.endLine) {
        return r;
      }
    }
    return new FoldRegion(-1, -1, false);
  }

  /**
   * 切换行首折叠块的开/关状态。
   */
  private toggleFold(line: number): void {
    const r = this.findFoldRegionAtLine(line);
    if (r.startLine < 0 || r.startLine !== line) {
      return;
    }
    r.collapsed = !r.collapsed;
    this.flashedFoldLine = line;
    setTimeout(() => { this.flashedFoldLine = -1; }, 400);
    const hiddenLines = r.endLine - r.startLine - 1;
    if (r.collapsed) {
      this.activeFoldCount += hiddenLines;
      const lines = this.getLines();
      r.hiddenText = lines.slice(r.startLine + 1, r.endLine + 1).join('\n');
    } else {
      this.activeFoldCount -= hiddenLines;
    }
    this.buildLineList();
    this.buildRenderTokens();
  }

  /**
   * 折叠当前光标所在块。
   */
  private foldCurrentBlock(): void {
    const r = this.findFoldRegionAtLine(this.currentLineNum);
    if (r.startLine < 0 || r.collapsed) {
      return;
    }
    r.collapsed = true;
    this.activeFoldCount += r.endLine - r.startLine - 1;
    const lines = this.getLines();
    r.hiddenText = lines.slice(r.startLine + 1, r.endLine + 1).join('\n');
    this.buildLineList();
    this.buildRenderTokens();
  }

  /**
   * 展开当前光标所在块。
   */
  private unfoldCurrentBlock(): void {
    const r = this.findFoldRegionAtLine(this.currentLineNum);
    if (r.startLine < 0 || !r.collapsed) {
      return;
    }
    r.collapsed = false;
    this.activeFoldCount -= r.endLine - r.startLine - 1;
    this.buildLineList();
    this.buildRenderTokens();
  }

  /** 外部折叠全部切换回调。 */
  onFoldAllChange(): void {
    this.buildLineList();
    if (this.foldAll) {
      for (const r of this.foldRegions) {
        r.collapsed = true;
      }
      this.activeFoldCount = this.foldRegions.length;
    } else {
      for (const r of this.foldRegions) {
        r.collapsed = false;
      }
      this.activeFoldCount = 0;
    }
    this.buildRenderTokens();
  }

  // ================================================================
  // 书签 (Bookmark)
  // ================================================================

  /** 检查某行是否有书签。 */
  private hasBookmark(line: number): boolean {
    return this.bookmarkedLines.has(line);
  }

  /** 切换当前行书签。 */
  private toggleBookmark(): void {
    const line = this.currentLineNum;
    if (this.bookmarkedLines.has(line)) {
      this.bookmarkedLines.delete(line);
    } else {
      this.bookmarkedLines.add(line);
    }
    this.buildLineList();
  }

  /** 切换指定行书签。 */
  private toggleBookmarkAtLine(line: number): void {
    if (this.bookmarkedLines.has(line)) {
      this.bookmarkedLines.delete(line);
    } else {
      this.bookmarkedLines.add(line);
    }
    this.buildLineList();
  }

  /**
   * 跳转到下一个书签。
   * 若光标后无书签则回到第一个书签（循环）。
   */
  private jumpNextBookmark(): void {
    const sorted = Array.from(this.bookmarkedLines).sort((a: number, b: number) => a - b);
    if (sorted.length === 0) {
      return;
    }
    const cur = this.currentLineNum;
    let found = sorted.find((v: number) => v > cur);
    if (found === undefined) {
      found = sorted[0];
    }
    const lines = this.getLines();
    let pos = 0;
    for (let i = 0; i < found && i < lines.length; i++) {
      pos += lines[i].length + 1;
    }
    this.textAreaController.caretPosition(pos);
  }

  // ================================================================
  // 滚动
  // ================================================================

  /**
   * 若当前行超出可视区域，自动滚动以保持光标可见。
   */
  private scrollToCurrentLine(): void {
    const cl = this.currentLineNum;
    const lh = this.lineH();
    const cy = cl * lh;
    const vh = 600; // 近似视口高度
    if (cy > this.lastScrollY + vh - lh * 2) {
      // 光标在视口下方 → 向下滚动
      const ns = Math.max(0, cy - vh + lh * 3);
      this.editorScroller.scrollTo({
        xOffset: 0, yOffset: ns,
        animation: { duration: 120, curve: Curve.Linear }
      });
      this.lastScrollY = ns;
    } else if (cy < this.lastScrollY) {
      // 光标在视口上方 → 向上滚动
      this.editorScroller.scrollTo({
        xOffset: 0, yOffset: cy,
        animation: { duration: 120, curve: Curve.Linear }
      });
      this.lastScrollY = cy;
    }
  }

  // ================================================================
  // 注释切换
  // ================================================================

  /**
   * 切换当前行注释：有 // 则去掉，无则添加。
   */
  private toggleComment(): void {
    const lines = this.editorText.split('\n');
    const cur = this.currentLineNum;
    if (cur >= lines.length) {
      return;
    }
    const line = lines[cur];
    let prefix = '//';
    if (this.language === 'python' || this.language === 'shell' || this.language === 'yaml' || this.language === 'toml') {
      prefix = '#';
    }
    lines[cur] = line.startsWith(prefix) ? line.substring(prefix.length) : prefix + line;
    const result = lines.join('\n');
    this.editorText = result;
    this.fullText = result;
    this.invalidateLines();
    this.updateTokens();
    this.buildLineList();
    if (this.onContentChange) {
      this.onContentChange(result);
    }
  }

  // Tab / Shift+Tab: 缩进 / 反缩进当前行
  private indentLine(dir: number): void {
    const lines = this.editorText.split('\n');
    const cur = this.currentLineNum;
    if (cur >= lines.length) return;
    const indent = this.getIndentStr();
    if (dir > 0) {
      lines[cur] = indent + lines[cur];
      this.trackedCursor += indent.length;
    } else {
      let cut = 0;
      for (let i = 0; i < indent.length && i < lines[cur].length; i++) {
        const c = lines[cur].charAt(i);
        if (c === ' ' || c === '\t') cut++; else break;
      }
      if (cut > 0) {
        lines[cur] = lines[cur].substring(cut);
        this.trackedCursor = Math.max(0, this.trackedCursor - cut);
      }
    }
    const result = lines.join('\n');
    this.editorText = result;
    this.fullText = result;
    this.invalidateLines();
    this.updateTokens();
    this.buildLineList();
    this.textAreaController.caretPosition(this.trackedCursor);
  }

  // Alt+Shift+A: 块注释切换 /* */（VS Code 风格）
  private toggleBlockComment(): void {
    const lines = this.editorText.split('\n');
    const cur = this.currentLineNum;
    if (cur >= lines.length) return;
    // 确定注释标记
    let open = '/*'; let close = '*/';
    if (this.language === 'python') { open = '"""'; close = '"""'; }
    else if (this.language === 'html' || this.language === 'xml') { open = '<!--'; close = '-->'; }
    else if (this.language === 'markdown') { open = '<!--'; close = '-->'; }
    const line = lines[cur];
    if (line.includes(open) && line.includes(close)) {
      // 移除块注释
      lines[cur] = line.replace(open, '').replace(close, '');
    } else {
      lines[cur] = open + line + close;
    }
    const result = lines.join('\n');
    this.editorText = result;
    this.fullText = result;
    this.invalidateLines();
    this.updateTokens();
    this.buildLineList();
    if (this.onContentChange) this.onContentChange(result);
  }

  // Ctrl+U / Ctrl+Shift+U: 单词大小写转换
  private transformWord(mode: string): void {
    const text = this.editorText; let cursor = this.trackedCursor;
    if (cursor < 0 || cursor > text.length) cursor = text.length;
    let start = cursor; while (start > 0 && this.isWordChar(text.charAt(start - 1))) start--;
    let end = cursor; while (end < text.length && this.isWordChar(text.charAt(end))) end++;
    if (start >= end) return;
    const word = text.substring(start, end);
    const transformed = mode === 'upper' ? word.toUpperCase() : word.toLowerCase();
    if (word === transformed) return;
    const t = text.substring(0, start) + transformed + text.substring(end);
    this.editorText = t;
    this.fullText = t;
    this.invalidateLines();
    this.updateTokens();
    this.buildLineList();
    if (this.onContentChange) this.onContentChange(t);
    setTimeout(() => { this.textAreaController.caretPosition(start + transformed.length); }, 0);
  }
  private isWordChar(ch: string): boolean {
    const c = ch.charCodeAt(0);
    return (c >= 65 && c <= 90) ||
      (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57) ||
      c === 95;
  }

  // ================================================================
  // 语法着色 & 搜索装饰 & 背景高亮
  // ================================================================

  /**
   * 根据 token 类型返回对应颜色。
   * 颜色方案：双主题 (light / dark)，适配 IntelliJ / VS Code 风格。
   */
  spanColor(tokenType: TokenType, startIndex: number): string {
    // 括号层级配色优先
    const level = this.bracketLevels.get(startIndex);
    if (level !== undefined && level > 0) {
      const idx = (level - 1) % EditorAreaImpl.BRACKET_COLORS.length;
      return EditorAreaImpl.BRACKET_COLORS[idx];
    }
    const isLight = this.currentColorMode === 'light';
    switch (tokenType) {
      case TokenType.KEYWORD:      return isLight ? '#0033B3' : '#CC7832';
      case TokenType.STRING:       return isLight ? '#067D17' : '#6A8759';
      case TokenType.COMMENT:      return isLight ? '#8C8C8C' : '#808080';
      case TokenType.NUMBER:       return isLight ? '#1750EB' : '#6897BB';
      case TokenType.FUNCTION:     return isLight ? '#00627A' : '#FFC66D';
      case TokenType.PREPROCESSOR: return isLight ? '#7A3E9D' : '#C586C0';
      default:                     return this.col().text;
    }
  }

  /**
   * 检查给定字符索引 si 是否落在任一搜索匹配区间内。
   * 若命中则返回下划线装饰，否则返回 None。
   */
  matchDecoration(si: number): TextDecorationType {
    if (this.searchMatches.length === 0 || this.searchLen <= 0) {
      return TextDecorationType.None;
    }
    for (let i = 0; i < this.searchMatches.length; i++) {
      if (si >= this.searchMatches[i] && si < this.searchMatches[i] + this.searchLen) {
        return TextDecorationType.Underline;
      }
    }
    return TextDecorationType.None;
  }

  /**
   * 判断 si 是否落在"当前选中"的搜索匹配项上（用于高亮区分）。
   */
  private inCurMatch(si: number): boolean {
    if (this.currentSearchIdx < 0 || this.currentSearchIdx >= this.searchMatches.length) {
      return false;
    }
    const ms = this.searchMatches[this.currentSearchIdx];
    return si >= ms && si < ms + this.searchLen;
  }

  /**
   * 综合背景色叠加，按优先级返回：
   *   1. 当前搜索匹配项（高亮）
   *   2. 括号对匹配项
   *   3. 当前行高亮
   *   4. 透明（无背景）
   */
  mergeBg(si: number): string {
    // 文本选中区域
    if (this.selectionStart !== this.selectionEnd && si >= this.selectionStart && si < this.selectionEnd) {
      return this.col().accentBg;
    }
    // 当前搜索匹配项
    if (this.inCurMatch(si)) {
      return this.flashActive ? this.col().highlightFind : this.col().accentBg;
    }
    // 括号匹配对
    if (this.bracketPair.length === 2) {
      if (si === this.bracketPair[0] || si === this.bracketPair[1]) {
        return this.col().bracketMatchBg;
      }
    }
    // 当前行背景
    if (si >= this.currentLineStart && si < this.currentLineEnd) {
      return this.col().currentLineBg;
    }
    // 选中词同亮
    if (this.wordHighlightPositions.length > 0) {
      for (let i = 0; i < this.wordHighlightPositions.length; i++) {
        if (si >= this.wordHighlightPositions[i] &&
            si < this.wordHighlightPositions[i] + this.wordHighlightLen) {
          return this.col().highlightFindAll;
        }
      }
    }
    return 'rgba(0,0,0,0)';
  }

  /**
   * 更新选中词高亮：找到光标所在单词的所有出现位置。
   */
  private updateWordHighlight(): void {
    this.wordHighlightPositions = [];
    this.wordHighlightLen = 0;
    const text = this.editorText;
    const pos = this.trackedCursor;
    if (pos < 0 || pos >= text.length) return;
    let start = pos;
    while (start > 0 && this.isWordCharAt(text, start - 1)) start--;
    let end = pos;
    while (end < text.length && this.isWordCharAt(text, end)) end++;
    const word = text.substring(start, end);
    if (word.length < 2) return;
    this.wordHighlightLen = word.length;
    let idx = 0;
    const maxHighlights = 100;
    while ((idx = text.indexOf(word, idx)) !== -1) {
      const bOk = idx === 0 || !this.isWordCharAt(text, idx - 1);
      const aOk = idx + word.length >= text.length || !this.isWordCharAt(text, idx + word.length);
      if (bOk && aOk) {
        this.wordHighlightPositions.push(idx);
        if (this.wordHighlightPositions.length >= maxHighlights) break;
      }
      idx++;
    }
  }

  private isWordCharAt(text: string, idx: number): boolean {
    const c = text.charCodeAt(idx);
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c === 95;
  }

  /**
   * 转义 % → %%，防止 Span 组件将 % 解释为格式化占位符。
   */


  /**
   * 折叠图标：▼ 展开 / ▶ 折叠 / 空格 无折叠。
   */
  private foldIcon(ind: FoldLineIndicator): string {
    if (!ind.isFoldStart) {
      return ' ';
    }
    return ind.isCollapsed ? '▶' : '▼';
  }

  /**
   * 生成缩进引导线字符串：每级缩进一个 "│"。
   * 防止 tabSize=0 引发除零。
   */
  private buildIndentGuide(ind: FoldLineIndicator): string {
    const ts = this.tabSize > 0 ? this.tabSize : 4;
    const level = Math.floor(ind.indentLevel / ts);
    if (level <= 0) {
      return '';
    }
    let guide = '';
    for (let i = 0; i < level; i++) {
      guide += '│';
    }
    return guide;
  }

  /**
   * 缩进引导线不透明度：当前行更明显，其余行淡化。
   */
  private guideOpacity(ind: FoldLineIndicator): number {
    return ind.lineNumber === this.currentLineNum ? 0.6 : 0.25;
  }

  // ================================================================
  // 生命周期
  // ================================================================

  /**
   * 组件初始化：同步外部文本、自动检测语言、构建初始 UI 数据。
   */
  aboutToAppear(): void {
    const clean = this.replaceCrlf(this.content);
    this.fullText = clean;
    this.editorText = clean;
    this.displayText = clean;
    this.invalidateLines();
    this.guessIndentation(clean);
    this.lastLang = this.language;
    if (this.language === 'plaintext') {
      const detected = this.detectLanguage();
      if (detected !== 'plaintext' && this.onLanguageDetect) {
        this.onLanguageDetect(detected);
      }
    }
    this.updateTokens();
    this.buildLineList();
    this.syncStats();
  }

  /**
   * 外部内容变更时同步（如文件切换）。
   */
  syncFromExternal(): void {
    const clean = this.replaceCrlf(this.content);
    if (clean === this.editorText) {
      return;
    }
    this.fullText = clean;
    this.editorText = clean;
    this.displayText = clean;
    this.invalidateLines();
    this.guessIndentation(clean);
    this.updateTokens();
    this.buildLineList();
    this.syncStats();
  }

  /**
   * 语言属性变更时重新生成 token。
   */
  onLanguagePropChange(): void {
    if (this.language !== this.lastLang) {
      this.lastLang = this.language;
      setTimeout(() => {
        this.updateTokens();
        this.buildLineList();
      }, 0);
    }
  }

  // ==================== 键盘快捷键 ====================

  private handleKeyPreIme(event: KeyEvent): boolean {
    if (event.type !== KeyType.Down) return false;
    let ctrl = false; let shift = false; let alt = false;
    if (event.getModifierKeyState !== undefined) {
      const cv = event.getModifierKeyState(['Ctrl']);
      if (cv !== undefined) {
        ctrl = cv;
      }
      const sv = event.getModifierKeyState(['Shift']);
      if (sv !== undefined) {
        shift = sv;
      }
      const av = event.getModifierKeyState(['Alt']);
      if (av !== undefined) {
        alt = av;
      }
    }
    const kc = event.keyCode;
    if (ctrl) {
      if (kc === 2035) { if (this.onSave) this.onSave(); return true; }
      if (kc === 2022 || kc === 2024) {
        if (this.onFindReplace) {
          this.onFindReplace();
        }
        return true;
      }
      if (kc === 2023) { if (this.onGoToLine) this.onGoToLine(); return true; }
      if (kc === 2042) { if (this.onUndo) this.onUndo(); return true; }
      if (kc === 2041) { if (this.onRedo) this.onRedo(); return true; }
      if (kc === 2020) { if (this.onDuplicateLine) this.onDuplicateLine(); return true; }
      if (kc === 2028) { this.selectCurrentLine(); return true; }
      // Ctrl+Shift+\ → 跳转到匹配括号
      if (shift && event.keyText === '\\') { this.jumpToMatchingBracket(); return true; }
      if (shift && kc === 2027) { if (this.onDeleteLine) this.onDeleteLine(); return true; }
      // 移动行（仅 Alt+↑/↓，Ctrl+Shift+↑/↓ 已移除）
      if (kc === 2064) { this.toggleComment(); return true; }
      if (kc === 2067) { this.toggleBookmark(); return true; }
      if (shift && kc === 2061) { this.foldCurrentBlock(); return true; }
      if (shift && kc === 2062) { this.unfoldCurrentBlock(); return true; }
      // Ctrl+Shift+P → 命令面板
      if (shift && event.keyText === 'P') {
        this.showCommandPalette = !this.showCommandPalette;
        this.cmdFilter = '';
        return true;
      }
      // Ctrl+Shift+O → 符号导航
      if (shift && event.keyText === 'O') {
        this.showSymbolPalette = !this.showSymbolPalette;
        this.cmdFilter = '';
        return true;
      }
      if (kc === 2037) {
        shift ? this.transformWord('upper') : this.transformWord('lower');
        return true;
      }
      if (event.keyText === '\n') {
        shift ? this.insertLineAbove() : this.insertLineBelow();
        return true;
      }
      // Ctrl+← → 单词导航
      if (kc === 2048) {
        const np = this.moveWordLeft(this.editorText, this.trackedCursor);
        this.textAreaController.caretPosition(np);
        this.trackedCursor = np;
        this.currentLineNum = this.lineFromPos(this.editorText, np);
        this.syncCurrentLineRange();
        return true;
      }
      if (kc === 2049) {
        const np = this.moveWordRight(this.editorText, this.trackedCursor);
        this.textAreaController.caretPosition(np);
        this.trackedCursor = np;
        this.currentLineNum = this.lineFromPos(this.editorText, np);
        this.syncCurrentLineRange();
        return true;
      }
    }
    // Tab → 代码片段展开 / 缩进；Shift+Tab → 反缩进
    if (kc === 2039) {
      if (shift) { this.indentLine(-1); return true; }
      if (this.tryExpandSnippet()) return true;
      this.indentLine(1);
      return true;
    }
    if (kc === 2057) { this.jumpNextBookmark(); return true; }
    // F1 → 命令面板
    if (kc === 2056) { this.showCommandPalette = !this.showCommandPalette; this.cmdFilter = ''; return true; }
    if (kc === 2070 && this.showShortcutsPanel) { this.showShortcutsPanel = false; return true; }
    // F11 → 关闭全屏
    if (kc === 2072 && !ctrl && !shift && !alt) {
      const v = AppStorage.get('fullscreen') as boolean ?? false;
      AppStorage.setOrCreate('fullscreen', !v);
      return true;
    }
    if (alt) {
      if (shift && kc === 2054) { if (this.onDuplicateLine) this.onDuplicateLine(); return true; }
      if (shift && kc === 2055) { if (this.onDuplicateLine) this.onDuplicateLine(); return true; }
      if (kc === 2054) { if (this.onMoveLineUp) this.onMoveLineUp(); return true; }
      if (kc === 2055) { if (this.onMoveLineDown) this.onMoveLineDown(); return true; }
      if (shift && event.keyText === 'A') { this.toggleBlockComment(); return true; }
    }
    return false;
  }

  private handleKeyEvent(event: KeyEvent): boolean {
    const kc = event.keyCode; const kt = event.keyText;
    if (kc === 2049 || kc === 9) {
      if (event.type !== KeyType.Down) return true;
      let shift = false;
      if (event.getModifierKeyState !== undefined) {
        const sv = event.getModifierKeyState(['Shift']);
        if (sv !== undefined) {
          shift = sv;
        }
      }
      shift ? this.outdentLine() : this.indentAtCursor();
      return true;
    }
    return false;
  }

  // ==================== UI ====================

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
      Scroll(this.editorScroller) {
      Row() {
        // VS Code: gutter and editor are top-aligned
        if (this.showLineNumbers) {
          // 合并列：折叠图标 + 书签标记
          Column() { ForEach(this.foldIndicators, (ind: FoldLineIndicator, idx: number) => {
            Row() {
              Text(this.foldIcon(ind))
                .fontSize(this.fontSize).fontFamily('monospace').lineHeight(this.lineH()).width(16)
                .textAlign(TextAlign.Center)
                .fontColor(ind.lineNumber === this.flashedFoldLine ? this.col().accent : this.col().textSecondary)
                .focusable(false)
                .onClick(() => { this.toggleFold(ind.lineNumber); })
              Text(this.hasBookmark(ind.lineNumber) ? '●' : ' ')
                .fontSize(this.fontSize * 0.6).fontFamily('monospace').lineHeight(this.lineH()).width(12)
                .textAlign(TextAlign.Center).fontColor('#007acc').focusable(false)
                .onClick(() => { this.toggleBookmarkAtLine(ind.lineNumber); })
            }
          }, (ind: FoldLineIndicator) => ind.lineNumber.toString()) }.padding({ top: 4 }).justifyContent(FlexAlign.Start)

          Column() { ForEach(this.foldIndicators, (ind: FoldLineIndicator, idx: number) => {
            Text((ind.lineNumber + 1).toString())
              .fontSize(this.fontSize).fontFamily('monospace').lineHeight(this.lineH())
              .fontColor(ind.lineNumber === this.currentLineNum ? this.col().accent : this.col().textSecondary)
              .fontWeight(ind.lineNumber === this.currentLineNum ? FontWeight.Bold : FontWeight.Normal)
              .textAlign(TextAlign.End).width(40).focusable(false)
          }, (ind: FoldLineIndicator) => ind.lineNumber.toString()) }.padding({ top: 4, right: 8 }).border({ width: { right: 1 }, color: this.col().border }).padding({ right: 8 }).justifyContent(FlexAlign.Start)
        }

        Column() {
          Stack({ alignContent: Alignment.TopStart }) {
            // 语法高亮层
            if (this.tokens.length > 0) {
              Text() {
                ForEach(this.renderTokens, (tok: TokenRender, i: number) => {
                  Span(tok.text)
                    .fontColor(this.spanColor(tok.tokenType, tok.startIndex))
                    .backgroundColor(this.mergeBg(tok.startIndex))
                    .decoration({ type: this.matchDecoration(tok.startIndex),
                                   color: this.col().searchMark })
                }, (tok: TokenRender, i: number) => tok.startIndex.toString() + ':' + tok.endIndex.toString() + ':' + tok.text.length.toString())
              }
              .fontSize(this.fontSize).fontFamily('monospace').lineHeight(this.lineH())
              .padding(4)
              .hitTestBehavior(HitTestMode.None).focusable(false)
            }
            if (this.tokens.length === 0) {
              Text(this.editorText)
                .fontSize(this.fontSize).fontColor(this.col().text).fontFamily('monospace')
                .lineHeight(this.lineH()).padding(4).width('100%').textAlign(TextAlign.Start)
                .hitTestBehavior(HitTestMode.None).focusable(false)
            }
            // 输入层（上层透明，接收所有触摸和焦点）
            TextArea({ text: this.editorText, controller: this.textAreaController })
              .fontSize(this.fontSize).fontFamily('monospace').lineHeight(this.lineH())
              .fontColor('rgba(0,0,0,0)').backgroundColor('rgba(0,0,0,0)')
              .padding(4).width('100%')
              .constraintSize({ minHeight: this.visibleLineCount * this.lineH() })
              .focusable(true).focusOnTouch(true).id(this.tabId + '_textarea')
              .onKeyPreIme((event: KeyEvent): boolean => { return this.handleKeyPreIme(event); })
              .onKeyEvent((event: KeyEvent): boolean => { return this.handleKeyEvent(event); })
              .onChange((value: string) => { this.handleTextChange(value); })
              .onTextSelectionChange((selectionStart: number, selectionEnd: number) => {
                this.handleSelectionChange(selectionStart, selectionEnd);
              })
              .onPaste((value: string, event: PasteEvent) => {
                const text = value;
                if (text && text.includes('\n') && this.trackedCursor >= 0) {
                  // 粘贴多行文本 → 自动调整缩进
                  setTimeout(() => {
                    this.autoIndentPaste();
                  }, 50);
                }
              })
          }
        }.layoutWeight(1).padding({ left: 4, right: 4, bottom: 4 })
        }.alignItems(VerticalAlign.Top)
    }.scrollBar(BarState.Auto).edgeEffect(EdgeEffect.Spring)
      .onScroll((xOffset: number, yOffset: number) => { this.onEditorScroll(xOffset, yOffset); })
      .align(Alignment.TopStart).backgroundColor(this.col().bg).layoutWeight(1)

    // Minimap
    if (this.showMinimap && this.editorText.length > 0) {
      Stack({ alignContent: Alignment.TopStart }) {
        Column() {
          ForEach(this.getLines(), (line: string, idx: number) => {
            Row()
              .width(Math.min(56, Math.max(4, line.length * 0.8)))
              .height(1)
              .backgroundColor(this.col().textSecondary)
              .opacity(0.3)
              .margin({ left: this.getLineIndent(line) * 0.5 })
          }, (line: string, idx: number) => idx.toString())
        }
        .width(60)
        .hitTestBehavior(HitTestMode.None)
        .focusable(false)

        Row()
          .width(60)
          .height(this.minimapSliderHeight())
          .backgroundColor(this.col().accent)
          .opacity(0.15)
          .offset({ y: this.minimapSliderOffset() })
          .hitTestBehavior(HitTestMode.None)
      }
      .width(60)
      .height('100%')
      .clip(true)
      .border({ width: { left: 1 }, color: this.col().border })
      .onClick((event: ClickEvent) => {
        const h = Number(event.target.area.height);
        if (h > 0) {
          const ratio = event.y / h;
          const totalH = this.getLines().length * this.lineH();
          this.editorScroller.scrollTo({ xOffset: 0, yOffset: ratio * totalH, animation: false });
        }
      })
    }
    }.width('100%').height('100%')

    if (this.showShortcutsPanel) {
      Column() {
        Column() {
          Text('⌨ 快捷键参考').fontSize(this.fontSize * 1.5).fontWeight(FontWeight.Bold).fontColor(this.col().text).margin({ bottom: 20 })

          Row() { Text('编辑').fontSize(this.fontSize * 0.75).fontColor(this.col().textSecondary).width(60); Text('Ctrl+S').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('保存').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('Ctrl+Z / Ctrl+Y').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('撤销 / 重做').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('Ctrl+D').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('复制当前行').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('Ctrl+Shift+K').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('删除当前行').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('Ctrl+Shift+[/]').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('折叠/展开块').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('Ctrl+/').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('切换注释').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('Tab / Shift+Tab').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('缩进 / 反缩进').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('Alt+↑ / Alt+↓').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('上/下移动行').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('Alt+Shift+↑/↓').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('复制行到上/下').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('Ctrl+Enter / Shift').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('下/上插入空行').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('Ctrl+U / Ctrl+Shift+U').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('单词小写 / 大写').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('导航').fontSize(this.fontSize * 0.75).fontColor(this.col().textSecondary).width(60); Text('Ctrl+F / Ctrl+H').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('查找 / 替换').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('Ctrl+G').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('跳转到行').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('Ctrl+E').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('跳转到匹配括号').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('Ctrl+L').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('跳到行首').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('F2').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('跳转下一个书签').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('Ctrl+F2').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('切换书签').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('窗口').fontSize(this.fontSize * 0.75).fontColor(this.col().textSecondary).width(60); Text('F1').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('快捷键参考').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')

          Row() { Text('').fontSize(this.fontSize * 0.75).width(60); Text('Ctrl+Shift+↑/↓').fontSize(this.fontSize * 0.85).fontFamily('monospace').fontColor(this.col().accentBg).width(150); Text('上/下移动行').fontSize(this.fontSize * 0.85).fontColor(this.col().text).layoutWeight(1) }.padding({ top: 6, bottom: 6 }).width('100%')
        }.padding(32).borderRadius(16).backgroundColor(this.col().bg).shadow({ radius: 32, color: 'rgba(0,0,0,0.3)', offsetX: 0, offsetY: 8 }).width('90%').constraintSize({ maxWidth: 560 })
      }.width('100%').height('100%').backgroundColor('rgba(0,0,0,0.4)').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center).onClick(() => { this.showShortcutsPanel = false; })
    }
    if (this.showCommandPalette) {
      Column() {
        // 搜索框
        TextInput({ text: this.cmdFilter, placeholder: '搜索命令...' })
          .fontSize(this.fontSize)
          .height(40)
          .width('90%')
          .backgroundColor(this.col().inputBg)
          .borderRadius(4)
          .border({ width: 1, color: this.col().accent })
          .padding({ left: 12, right: 12 })
          .margin({ top: 16, bottom: 8 })
          .focusable(true)
          .focusOnTouch(true)
          .onChange((v: string) => { this.cmdFilter = v; })

        // 命令列表（可滚动）
        Scroll() {
          Column() {
            ForEach(this.getCommandPaletteItems(), (cmd: CommandItem) => {
              Row() {
                Text(cmd.label)
                  .fontSize(this.fontSize * 0.9)
                  .fontColor(this.col().text)
                  .layoutWeight(1)
                Text(cmd.key)
                  .fontSize(this.fontSize * 0.75)
                  .fontColor(this.col().textSecondary)
                  .fontFamily('monospace')
              }
              .width('100%').padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .onClick(() => { this.execCommand(cmd.label); })
            }, (cmd: CommandItem) => cmd.label)
          }
          .width('100%').alignItems(HorizontalAlign.Start)
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .width('100%')
      }
      .width('90%')
      .height('60%')
      .constraintSize({ maxWidth: 560, maxHeight: 480 })
      .backgroundColor(this.col().bg)
      .borderRadius(8)
      .shadow({ radius: 32, color: 'rgba(0,0,0,0.4)', offsetX: 0, offsetY: 8 })
      .border({ width: 1, color: this.col().border })
    }
    if (this.showSymbolPalette) {
      Column() {
        TextInput({ text: this.cmdFilter, placeholder: '搜索符号 (函数/类/结构体)...' })
          .fontSize(this.fontSize).height(40).width('90%')
          .backgroundColor(this.col().inputBg).borderRadius(4)
          .border({ width: 1, color: this.col().accent })
          .padding({ left: 12, right: 12 }).margin({ top: 16, bottom: 8 })
          .focusable(true).focusOnTouch(true)
          .onChange((v: string) => { this.cmdFilter = v; })
        Scroll() {
          Column() {
            ForEach(this.getSymbolItems(), (s: SymbolItem) => {
              Row() {
                Text(s.kind).fontSize(this.fontSize * 0.75).fontColor(this.col().accent)
                  .width(48).fontFamily('monospace')
                Text(s.label).fontSize(this.fontSize * 0.9).fontColor(this.col().text).layoutWeight(1)
                Text('行 ' + s.line).fontSize(this.fontSize * 0.75).fontColor(this.col().textSecondary)
              }
              .width('100%').padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .onClick(() => { this.goToSymbol(s.line); })
            }, (s: SymbolItem) => s.line.toString() + s.label)
          }
        }
        .scrollBar(BarState.Off).layoutWeight(1).width('100%')
      }
      .width('90%').height('60%')
      .constraintSize({ maxWidth: 560, maxHeight: 480 })
      .backgroundColor(this.col().bg).borderRadius(8)
      .shadow({ radius: 32, color: 'rgba(0,0,0,0.4)', offsetX: 0, offsetY: 8 })
      .border({ width: 1, color: this.col().border })
    }
    }.width('100%').height('100%')
  }
}