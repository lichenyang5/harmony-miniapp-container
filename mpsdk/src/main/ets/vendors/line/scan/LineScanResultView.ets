import { LineScanResultAction, LineScanResultViewParams } from './LineScanResultTypes';

@Builder
function buildLineScanResult(params: LineScanResultViewParams) {
  LineScanResultView({ params })
}

export const lineScanResultBuilder: WrappedBuilder<[LineScanResultViewParams]> = wrapBuilder(buildLineScanResult);

/** 系统扫码页返回后展示内容，长结果可滚动，所有操作由用户主动触发。 */
@ComponentV2
struct LineScanResultView {
  @Require @Once @Param params: LineScanResultViewParams;

  build() {
    Column({ space: 20 }) {
      Text($r('app.string.mp_line_scan_result_title'))
        .fontSize(20).fontWeight(FontWeight.Medium).fontColor('#111111').width('100%')
      Scroll() {
        Text(this.params.value)
          .fontSize(16).fontColor('#333333').width('100%').wordBreak(WordBreak.BREAK_ALL)
      }.width('100%').height(160).align(Alignment.TopStart)
      Button(this.params.isLink ? $r('app.string.mp_line_scan_result_open') : $r('app.string.mp_line_scan_result_copy'))
        .width('100%').height(48).borderRadius(8).backgroundColor('#06C755').fontColor(Color.White)
        .onClick((): void => {
          this.params.complete(this.params.isLink ? LineScanResultAction.OPEN : LineScanResultAction.COPY);
        })
      Row() {
        if (this.params.isLink) {
          Button($r('app.string.mp_line_scan_result_copy'), { type: ButtonType.Normal })
            .layoutWeight(1).height(40).backgroundColor(Color.Transparent).fontColor('#111111')
            .onClick((): void => this.params.complete(LineScanResultAction.COPY))
        }
        Button($r('app.string.mp_line_scan_result_close'), { type: ButtonType.Normal })
          .layoutWeight(1).height(40).backgroundColor(Color.Transparent).fontColor('#777777')
          .onClick((): void => this.params.complete(LineScanResultAction.CLOSE))
      }.width('100%')
    }.width('90%').constraintSize({ maxWidth: 360 }).padding(24)
    .backgroundColor(Color.White).borderRadius(20)
  }
}
