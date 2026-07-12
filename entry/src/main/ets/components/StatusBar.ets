import { ThemeColors } from '../utils/ThemeColors'

@Component
export struct StatusBarImpl {
  @Prop fileType: string = '纯文本'
  @Prop fileEncoding: string = 'UTF-8'
  @Prop eolDisplay: string = 'LF'
  @Prop insertMode: boolean = true
  @Prop totalLines: number = 1
  @Prop totalChars: number = 0
  @Prop cursorLine: number = 1
  @Prop cursorColumn: number = 1
  @Prop cursorPulse: number = 1.0
  @Prop selectionStats: string = ''
  @Prop indentType: string = '空格:4'
  @StorageProp('currentColorMode') currentColorMode: string = 'light'

  @BuilderParam langMenuBuilder: () => void
  @BuilderParam encodingMenuBuilder: () => void

  onEolClick?: () => void
  onInsertModeClick?: () => void
  onCursorClick?: () => void

  private col(): ThemeColors {
    return ThemeColors.forMode(this.currentColorMode)
  }

  build() {
    Row() {
      Text(this.fileType)
        .fontSize(12)
        .fontColor(this.col().textSecondary)
        .padding({ left: 12, right: 8 })
        .bindMenu(this.langMenuBuilder)

      Text('  ' + this.fileEncoding)
        .fontSize(12)
        .fontColor(this.col().textSecondary)
        .padding({ left: 4, right: 4 })
        .bindMenu(this.encodingMenuBuilder)

      Text('  ' + this.eolDisplay)
        .fontSize(12)
        .fontColor(this.col().textSecondary)
        .padding({ left: 4, right: 4 })
        .onClick(() => {
          if (this.onEolClick) {
            this.onEolClick()
          }
        })

      Text('  ' + (this.insertMode ? '插入' : '覆盖'))
        .fontSize(12)
        .fontColor(this.col().textSecondary)
        .padding({ left: 4, right: 4 })
        .onClick(() => {
          if (this.onInsertModeClick) {
            this.onInsertModeClick()
          }
        })

      Text('  ' + this.indentType)
        .fontSize(12)
        .fontColor(this.col().textSecondary)
        .padding({ left: 4, right: 4 })

      Divider()
        .vertical(true)
        .height(14)
        .color(this.col().divider)

      Text('共 ' + this.totalLines + ' 行 · ' + this.totalChars + ' 字')
        .fontSize(12)
        .fontColor(this.col().textSecondary)
        .padding({ left: 8, right: 8 })

      Text(this.selectionStats)
        .fontSize(12)
        .fontColor(this.col().accent)
        .padding({ left: 8, right: 8 })

      Blank()

      Text('行: ' + this.cursorLine + '  列: ' + this.cursorColumn)
        .fontSize(12)
        .fontColor(this.col().textSecondary)
        .scale({ x: this.cursorPulse, y: this.cursorPulse })
        .padding({ left: 8, right: 8 })
        .onClick(() => {
          if (this.onCursorClick) {
            this.onCursorClick()
          }
        })
    }
    .width('100%')
    .height(24)
    .backgroundColor(this.col().statusBarBg)
    .animation({ duration: 100, curve: Curve.Linear })
    .border({ width: { top: 1 }, color: this.col().border })
    .alignItems(VerticalAlign.Center)
  }
}
