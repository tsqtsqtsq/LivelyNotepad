import { ThemeColors } from '../utils/ThemeColors';

interface ShortcutEntry {
  section: string;
  keys: string;
  desc: string;
}

const SHORTCUTS: ShortcutEntry[] = [
  { section: '编辑', keys: 'Ctrl+S', desc: '保存' },
  { section: '', keys: 'Ctrl+Z / Ctrl+Y', desc: '撤销 / 重做' },
  { section: '', keys: 'Ctrl+D', desc: '复制当前行' },
  { section: '', keys: 'Ctrl+Shift+K', desc: '删除当前行' },
  { section: '', keys: 'Ctrl+Shift+[/]', desc: '折叠/展开块' },
  { section: '', keys: 'Ctrl+/', desc: '切换注释' },
  { section: '', keys: 'Tab / Shift+Tab', desc: '缩进 / 反缩进' },
  { section: '', keys: 'Alt+\u2191 / Alt+\u2193', desc: '上/下移动行' },
  { section: '', keys: 'Alt+Shift+\u2191/\u2193', desc: '复制行到上/下' },
  { section: '', keys: 'Ctrl+Enter / Shift', desc: '下/上插入空行' },
  { section: '', keys: 'Ctrl+U / Ctrl+Shift+U', desc: '单词小写 / 大写' },
  { section: '导航', keys: 'Ctrl+F / Ctrl+H', desc: '查找 / 替换' },
  { section: '', keys: 'Ctrl+G', desc: '跳转到行' },
  { section: '', keys: 'Ctrl+E', desc: '跳转到匹配括号' },
  { section: '', keys: 'Ctrl+L', desc: '跳到行首' },
  { section: '', keys: 'F2', desc: '跳转下一个书签' },
  { section: '', keys: 'Ctrl+F2', desc: '切换书签' },
  { section: '窗口', keys: 'F1', desc: '快捷键参考' },
];

@Component
export struct ShortcutsPanel {
  @Prop fontSize: number = 16;
  @Prop bgColor: string = '#1E1E1E';
  @Prop textColor: string = '#CCCCCC';
  @Prop mutedColor: string = '#888888';
  @Prop accentColor: string = '#264F78';
  onClose: () => void = () => {};

  build() {
    Column() {
      Column() {
        Text('\u2328 快捷键参考')
          .fontSize(this.fontSize * 1.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.textColor)
          .margin({ bottom: 20 })

        ForEach(SHORTCUTS, (entry: ShortcutEntry, index: number) => {
          Row() {
            Text(entry.section.length > 0 ? entry.section : '')
              .fontSize(this.fontSize * 0.75)
              .fontColor(entry.section.length > 0 ? this.mutedColor : 'rgba(0,0,0,0)')
              .width(60)
            Text(entry.keys)
              .fontSize(this.fontSize * 0.85)
              .fontFamily('monospace')
              .fontColor(this.accentColor)
              .width(150)
            Text(entry.desc)
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.textColor)
              .layoutWeight(1)
          }
          .padding({ top: 6, bottom: 6 })
          .width('100%')
        }, (entry: ShortcutEntry, index: number) => index.toString())
      }
      .padding(32)
      .borderRadius(16)
      .backgroundColor(this.bgColor)
      .shadow({ radius: 32, color: 'rgba(0,0,0,0.3)', offsetX: 0, offsetY: 8 })
      .width('90%')
      .constraintSize({ maxWidth: 560 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0,0,0,0.4)')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => { this.onClose(); })
  }
}
