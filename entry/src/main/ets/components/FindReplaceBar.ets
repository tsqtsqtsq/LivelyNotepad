import { ThemeColors } from '../utils/ThemeColors';

/**
 * 查找替换栏组件
 *
 * 提供 VS Code 风格的查找/替换能力：
 * - 实时搜索匹配（防抖 200ms）
 * - 区分大小写 / 全词匹配
 * - 上下导航 + 循环提示
 * - 单个替换 / 全部替换
 * - ESC 关闭
 */
@Component
export struct FindReplaceBarImpl {
  @Prop @Watch('doSearch') editorText: string = '';
  @StorageProp('currentColorMode') currentColorMode: string = 'dark';
  @State searchText: string = '';
  @State replaceText: string = '';
  @State caseSensitive: boolean = false;
  @State wholeWord: boolean = false;
  @State useRegex: boolean = false;
  @State showReplace: boolean = false;
  @State matchCount: number = 0;
  @State currentMatch: number = 0;
  @State wrapMsg: string = '';
  @State hoverReplace: boolean = false;
  @State hoverReplaceAll: boolean = false;

  // 回调
  onClose: () => void = () => {};
  onReplace: (newText: string) => void = (_newText: string) => {};
  onFindJump: (pos: number, len: number) => void = (_pos: number, _len: number) => {};
  onSearchUpdate: (matches: number[], currentIdx: number, len: number) => void =
    (_matches: number[], _currentIdx: number, _len: number) => {};

  // 内部状态
  private matchPositions: number[] = [];
  private matchLengths: number[] = [];
  private searchTimer: number = -1;
  private doSearchTimer: number = -1;

// ================================================================
// 主题快捷方法
// ================================================================

private col(): ThemeColors {
  return ThemeColors.forMode(this.currentColorMode);
}
private bg(): string {
  return this.col().surface;
}
private bdr(): string {
  return this.col().border;
}
private inputBg(): string {
  return this.col().inputBg;
}
private txt(): string {
  return this.col().text;
}
private mute(): string {
  return this.col().textSecondary;
}
private accent(): string {
  return this.col().accent;
}

// ================================================================
// 字符工具
// ================================================================

/** 判断是否为单词字符（字母/数字/下划线），用于全词匹配边界检测。 */
private isWordChar(code: number): boolean {
  return (code >= 48 && code <= 57) ||
    (code >= 65 && code <= 90) ||
    (code >= 97 && code <= 122) ||
    code === 95;
}

// ================================================================
// 搜索逻辑
// ================================================================

/**
 * 执行全文搜索。
 * 通过 setTimeout 将搜索推迟到下一帧，避免每次按键都触发 O(n) 扫描。
 * 支持区分大小写和全词匹配选项。
 */
doSearch(): void {
  const st = this.searchText;
  const et = this.editorText;
  const cs = this.caseSensitive;
  const ww = this.wholeWord;
  const rx = this.useRegex;
  clearTimeout(this.doSearchTimer);
  this.doSearchTimer = setTimeout(() => {
    this.matchPositions = [];
    this.matchLengths = [];
    this.currentMatch = 0;
    if (!st || et.length === 0) {
      this.matchCount = 0;
      this.onSearchUpdate([], -1, 0);
      return;
    }
    // 正则搜索
    if (rx) {
      try {
        const flags = cs ? 'gm' : 'gim';
        const re = new RegExp(st, flags);
        let m: RegExpExecArray | null;
        while ((m = re.exec(et)) !== null) {
          this.matchPositions.push(m.index);
          this.matchLengths.push(m[0].length);
          if (m[0].length === 0) {
            re.lastIndex++;
          }
        }
      } catch (_) {
        this.matchCount = 0;
        this.onSearchUpdate([], -1, 0);
        return;
      }
    } else {
      // 普通搜索（含大小写 + 全词）
      const src = cs ? et : et.toLowerCase();
      const needle = cs ? st : st.toLowerCase();
      const nLen = needle.length;
      let idx = 0;
      while ((idx = src.indexOf(needle, idx)) !== -1) {
        let ok = true;
        if (ww) {
          const bOk = idx === 0 || !this.isWordChar(et.charCodeAt(idx - 1));
          const aOk = idx + nLen >= et.length || !this.isWordChar(et.charCodeAt(idx + nLen));
          ok = bOk && aOk;
        }
        if (ok) {
          this.matchPositions.push(idx);
          this.matchLengths.push(nLen);
        }
        idx++;
      }
    }
    this.matchCount = this.matchPositions.length;
    if (this.matchPositions.length > 0) {
      this.currentMatch = 1;
      const len = this.matchLengths[0];
      this.onFindJump(this.matchPositions[0], len);
      this.onSearchUpdate(this.matchPositions, 0, len);
    } else {
      this.onSearchUpdate([], -1, 0);
    }
  }, 0);
}

// ================================================================
// 查找导航（上一个 / 下一个）
// ================================================================

/** 跳转到上一个匹配项。到达第一个后循环到最后一个。 */
private findPrev(): void {
  if (this.matchPositions.length === 0) {
    return;
  }
  const wasFirst = this.currentMatch <= 1;
  this.currentMatch = wasFirst ? this.matchPositions.length : this.currentMatch - 1;
  const idx = this.currentMatch - 1;
  const len = this.matchLengths.length > idx ? this.matchLengths[idx] : 0;
  this.onFindJump(this.matchPositions[idx], len);
  this.onSearchUpdate(this.matchPositions, idx, len);
  if (wasFirst) {
    this.showWrap('已循环，从最后一个开始');
  }
}

/** 跳转到下一个匹配项。到达最后一个后循环到第一个。 */
private findNext(): void {
  if (this.matchPositions.length === 0) {
    return;
  }
  const wasLast = this.currentMatch >= this.matchPositions.length;
  this.currentMatch = wasLast ? 1 : this.currentMatch + 1;
  const idx = this.currentMatch - 1;
  const len = this.matchLengths.length > idx ? this.matchLengths[idx] : 0;
  this.onFindJump(this.matchPositions[idx], len);
  this.onSearchUpdate(this.matchPositions, idx, len);
  if (wasLast) {
    this.showWrap('已循环，从第一个开始');
  }
}

/** 显示临时提示消息（循环提示），1.5s 后自动消失。 */
private showWrap(msg: string): void {
  this.wrapMsg = msg;
  setTimeout(() => {
    this.wrapMsg = '';
  }, 1500);
}

// ================================================================
// 替换逻辑
// ================================================================

/** 替换当前匹配项。 */
private replaceOne(): void {
  if (!this.searchText || this.matchPositions.length === 0) {
    return;
  }
  const idx = this.currentMatch - 1;
  if (idx < 0 || idx >= this.matchPositions.length) {
    return;
  }
  const pos = this.matchPositions[idx];
  const len = this.matchLengths.length > idx ? this.matchLengths[idx] : 0;
  const newText = this.editorText.substring(0, pos) +
    this.replaceText +
    this.editorText.substring(pos + len);
  this.onReplace(newText);
}

/**
 * 替换所有匹配项。
 * 从后往前替换以避免索引偏移问题。
 */
private replaceAll(): void {
  if (!this.searchText || this.matchPositions.length === 0) {
    return;
  }
  let result = this.editorText;
  // 从后往前替换，位置不会偏移
  for (let i = this.matchPositions.length - 1; i >= 0; i--) {
    const pos = this.matchPositions[i];
    const len = this.matchLengths.length > i ? this.matchLengths[i] : 0;
    result = result.substring(0, pos) + this.replaceText + result.substring(pos + len);
  }
  this.onReplace(result);
}

// ================================================================
// UI 构建
// ================================================================

build() {
  Column() {
    // ---- 查找行 ----
    Row() {
      TextInput({ placeholder: '查找', text: this.searchText })
        .layoutWeight(1)
        .height(32)
        .fontSize(14)
        .fontColor(this.txt())
        .backgroundColor(this.inputBg())
        .borderRadius(4)
        .border({ width: 1, color: this.bdr() })
        .onKeyEvent((event: KeyEvent): boolean => {
          if (event.type === KeyType.Down && (event.keyCode === 27 || event.keyCode === 2055)) {
            this.onClose();
            return true;
          }
          return false;
        })
        .onChange((value: string): void => {
          this.searchText = value;
          clearTimeout(this.searchTimer);
          if (!value) {
            this.doSearch();
          } else {
            this.searchTimer = setTimeout((): void => {
              this.doSearch();
            }, 200);
          }
        })

      // 匹配计数 / 循环提示
      Text(this.wrapMsg ? this.wrapMsg :
        (this.matchCount > 0 ? ('第' + this.currentMatch + '/' + this.matchCount) : ''))
        .fontSize(12)
        .fontColor(this.wrapMsg ? this.accent() : this.mute())
        .margin({ left: 4 })
        .width(this.wrapMsg ? 120 : 50)

      // 上一个
      Button('▲', { type: ButtonType.Capsule })
        .buttonStyle(ButtonStyleMode.NORMAL)
        .controlSize(ControlSize.SMALL)
        .backgroundColor(Color.Transparent)
        .fontColor(this.txt())
        .focusable(false)
        .onClick(() => { this.findPrev(); })

      // 下一个
      Button('▼', { type: ButtonType.Capsule })
        .buttonStyle(ButtonStyleMode.NORMAL)
        .controlSize(ControlSize.SMALL)
        .backgroundColor(Color.Transparent)
        .fontColor(this.txt())
        .focusable(false)
        .onClick(() => { this.findNext(); })

      // 关闭
      Button('✕', { type: ButtonType.Capsule })
        .buttonStyle(ButtonStyleMode.NORMAL)
        .controlSize(ControlSize.SMALL)
        .backgroundColor(Color.Transparent)
        .fontColor(this.txt())
        .fontSize(14)
        .focusable(false)
        .onClick(() => { this.onClose(); })
    }
    .width('100%')
    .height(36)
    .padding({ left: 8, right: 4 })
    .alignItems(VerticalAlign.Center)

    // ---- 选项行 ----
    Row() {
      // 区分大小写开关
      Row() {
        Text('区分大小写').fontSize(12).fontColor(this.txt())
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.caseSensitive })
          .selectedColor(this.accent())
          .width(36)
          .onChange((isOn: boolean) => {
            this.caseSensitive = isOn;
            this.doSearch();
          })
      }.margin({ right: 8 })

      // 全词匹配开关
      Row() {
        Text('全词匹配').fontSize(12).fontColor(this.txt())
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.wholeWord })
          .selectedColor(this.accent())
          .width(36)
          .onChange((isOn: boolean) => {
            this.wholeWord = isOn;
            this.doSearch();
          })
      }.margin({ right: 8 })

      // 正则表达式开关
      Row() {
        Text('正则').fontSize(12).fontColor(this.txt())
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.useRegex })
          .selectedColor(this.accent())
          .width(36)
          .onChange((isOn: boolean) => {
            this.useRegex = isOn;
            this.doSearch();
          })
      }.margin({ right: 8 })

      Blank()

      // 替换面板开关
      Row() {
        Text('替换').fontSize(12)
          .fontColor(this.showReplace ? this.accent() : this.txt())
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.showReplace })
          .selectedColor(this.accent())
          .width(36)
          .onChange((isOn: boolean) => {
            this.showReplace = isOn;
          })
      }
    }
    .width('100%')
    .height(32)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)

    // ---- 替换行（仅在开关打开时显示）----
    if (this.showReplace) {
      Row() {
        TextInput({ placeholder: '替换为', text: this.replaceText })
          .layoutWeight(1)
          .height(32)
          .fontSize(14)
          .fontColor(this.txt())
          .backgroundColor(this.inputBg())
          .borderRadius(4)
          .border({ width: 1, color: this.bdr() })
          .onChange((value: string) => {
            this.replaceText = value;
          })

        // 替换当前按钮
        Button('替换', { type: ButtonType.Capsule })
          .buttonStyle(ButtonStyleMode.NORMAL)
          .controlSize(ControlSize.SMALL)
          .fontSize(12)
          .height(28)
          .margin({ left: 4 })
          .backgroundColor(this.hoverReplace ? this.col().hoverBg : this.inputBg())
          .fontColor(this.txt())
          .focusable(false)
          .animation({ duration: 150, curve: Curve.Smooth })
          .onHover((isHover: boolean) => { this.hoverReplace = isHover; })
          .onClick(() => { this.replaceOne(); })

        // 全部替换按钮
        Button('全部', { type: ButtonType.Capsule })
          .buttonStyle(ButtonStyleMode.NORMAL)
          .controlSize(ControlSize.SMALL)
          .fontSize(12)
          .height(28)
          .margin({ left: 2 })
          .backgroundColor(this.hoverReplaceAll ? this.col().hoverBg : this.inputBg())
          .fontColor(this.txt())
          .focusable(false)
          .animation({ duration: 150, curve: Curve.Smooth })
          .onHover((isHover: boolean) => { this.hoverReplaceAll = isHover; })
          .onClick(() => { this.replaceAll(); })
      }
      .width('100%')
      .height(36)
      .padding({ left: 8, right: 4 })
    }
  }
  .backgroundColor(this.bg())
  .border({ width: { top: 1 }, color: this.bdr() })
  .padding({ top: 4, bottom: 4 })
}
}