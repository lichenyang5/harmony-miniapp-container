import { webview } from '@kit.ArkWeb';
import { window } from '@kit.ArkUI';
import { MiniAppSession } from '../../core/Runtime';
import { MiniAppError } from '../../core/MiniAppError';
import { MiniAppView } from '../../web/MiniAppView';
import { LineDialogInsets, readLineDialogInsets } from './LineDialogInsets';
import {
  computeLineDialogLayout,
  LINE_DIALOG_CLOSE_FONT_SIZE,
  LINE_DIALOG_CLOSE_HEIGHT,
  LINE_DIALOG_CLOSE_ICON_MARGIN,
  LINE_DIALOG_CLOSE_ICON_SIZE,
  LINE_DIALOG_CLOSE_LABEL_MARGIN,
  LineDialogLayout
} from './LineDialogLayout';
import { LineSubViewCloseButtonPosition, LineSubViewPresentation } from './liff/LineSubViewPresentation';

export interface LineDialogParams {
  hostWindow: window.Window;
  presentation: LineSubViewPresentation;
  session: MiniAppSession;
  headers: webview.WebHeader[];
  requestClose: () => void;
  onFailure: (error: MiniAppError) => void;
}

@Builder
function buildLineDialog(params: LineDialogParams) {
  LineDialogView({ params })
}

export const lineDialogBuilder: WrappedBuilder<[LineDialogParams]> = wrapBuilder(buildLineDialog);

/** 只承载 LINE 子页面，不创建或释放父会话。 */
@ComponentV2
struct LineDialogView {
  @Require @Once @Param params: LineDialogParams;
  @Local private insets: LineDialogInsets = { top: 0, right: 0, bottom: 0, left: 0 };
  @Local private layout: LineDialogLayout = { width: 0, height: 0, topCornerRadius: 0 };
  private active: boolean = false;
  private listeningSize: boolean = false;
  private listeningInsets: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.updateLayout();
    try {
      this.params.hostWindow.on('windowSizeChange', this.windowSizeChanged);
      this.listeningSize = true;
    } catch (_) { /* 不支持监听的窗口保留初始布局。 */
    }
    try {
      this.params.hostWindow.on('avoidAreaChange', this.avoidAreaChanged);
      this.listeningInsets = true;
    } catch (_) { /* 独立注册，尺寸监听失败不阻止安全区监听。 */
    }
  }

  aboutToDisappear(): void {
    this.active = false;
    if (this.listeningSize) {
      this.listeningSize = false;
      try {
        this.params.hostWindow.off('windowSizeChange', this.windowSizeChanged);
      } catch (_) { /* 窗口可能已销毁，继续清理其他监听。 */
      }
    }
    if (this.listeningInsets) {
      this.listeningInsets = false;
      try {
        this.params.hostWindow.off('avoidAreaChange', this.avoidAreaChanged);
      } catch (_) { /* 窗口可能已销毁。 */
      }
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
      }.width('100%').height('100%').backgroundColor(Color.Transparent)
      .onClick((): void => {
        this.requestClose();
      })

      Stack({ alignContent: this.params.presentation.closeButtonPosition === LineSubViewCloseButtonPosition.LEFT ?
        Alignment.TopStart : Alignment.TopEnd }) {
        MiniAppView({
          session: this.params.session,
          initialHeaders: this.params.headers,
          onError: (error: MiniAppError): void => {
            this.params.onFailure(error);
          }
        }).width('100%').height('100%')

        // 只覆盖关闭入口本身；同高度的其余区域仍由网页接收操作。
        if (this.params.presentation.hideCloseButton !== true) {
          this.closeButton()
        }
      }.width(this.layout.width).height(this.layout.height).backgroundColor(Color.White)
      .borderRadius({ topLeft: this.layout.topCornerRadius, topRight: this.layout.topCornerRadius,
        bottomLeft: 0, bottomRight: 0 })
      .clip(true)
      .hitTestBehavior(HitTestMode.Default)
    }.width('100%').height('100%').padding(this.insets).backgroundColor(Color.Transparent)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END])
  }

  @Builder
  private closeButton() {
    Button({ type: ButtonType.Normal }) {
      if (this.params.presentation.closeButtonLabel) {
        Text(this.params.presentation.closeButtonLabel)
          .fontSize(LINE_DIALOG_CLOSE_FONT_SIZE)
          .fontColor(Color.Black)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(LINE_DIALOG_CLOSE_ICON_SIZE)
          .width(LINE_DIALOG_CLOSE_ICON_SIZE).height(LINE_DIALOG_CLOSE_ICON_SIZE)
          .fontColor([Color.Black])
      }
    }.height(LINE_DIALOG_CLOSE_HEIGHT).constraintSize({ maxWidth: '100%' })
    .padding({ left: this.params.presentation.closeButtonLabel ?
      LINE_DIALOG_CLOSE_LABEL_MARGIN : LINE_DIALOG_CLOSE_ICON_MARGIN,
      right: this.params.presentation.closeButtonLabel ? LINE_DIALOG_CLOSE_LABEL_MARGIN : LINE_DIALOG_CLOSE_ICON_MARGIN })
    .borderRadius(0)
    .backgroundColor(Color.Transparent)
    .accessibilityText(this.closeButtonAccessibilityText())
    .hitTestBehavior(HitTestMode.Block)
    .onClick((): void => {
      this.requestClose();
    })
  }

  private requestClose(): void {
    if (this.active) {
      this.params.requestClose();
    }
  }

  private closeButtonAccessibilityText(): string {
    return this.params.presentation.closeButtonLabel || this.getUIContext()
      .getHostContext()?.resourceManager.getStringSync($r('app.string.mp_line_subwindow_close')) || '';
  }

  private readonly windowSizeChanged: (size: window.Size) => void = (_size: window.Size): void => {
    if (this.active) {
      this.updateLayout();
    }
  };

  private readonly avoidAreaChanged: (event: window.AvoidAreaOptions) => void =
    (_event: window.AvoidAreaOptions): void => {
      if (this.active) {
        this.updateLayout();
      }
    };

  private updateLayout(): void {
    const uiContext = this.getUIContext();
    this.insets = readLineDialogInsets(this.params.hostWindow,
      (value: number): number => uiContext.px2vp(value));
    try {
      const rect = this.params.hostWindow.getWindowProperties().windowRect;
      this.layout = computeLineDialogLayout(uiContext.px2vp(rect.width), uiContext.px2vp(rect.height),
        this.insets, this.params.presentation.presentationType);
    } catch (_) { /* 窗口销毁期间保留最后一次有效布局，不回调已退出的子页面。 */
    }
  }
}
