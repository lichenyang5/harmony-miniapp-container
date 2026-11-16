import { LineLoginActions, LineLoginState } from '../LineLoginTypes';
import { LineErrorCode, LineServiceErrorCode } from '../../LineErrorCode';
import { window } from '@kit.ArkUI';
import { LineDialogInsets, readLineDialogInsets } from '../../LineDialogInsets';

const EMAIL_INPUT_HEIGHT: number = 48;
const EMAIL_INPUT_GAP: number = 16;
const EMAIL_FORM_TOP: number = 40;
const LOGIN_BOTTOM_PADDING: number = 24;

@ObservedV2
export class LineLoginViewModel {
  @Trace state: LineLoginState = { phase: 'loading', method: 'qr' };
  @Trace email: string = '';
  @Trace password: string = '';
  @Trace dismissed: boolean = false;
  @Trace forgot: boolean = false;
  // 由挂载的视图提供；返回 true 表示本次返回仅用于收起输入法。
  dismissKeyboard?: () => boolean;

  update(state: LineLoginState): void {
    if (state.phase !== this.state.phase || state.pin !== this.state.pin || state.errorCode !== this.state.errorCode) {
      this.dismissed = false;
    }
    this.state = state;
  }

  clearSecrets(): void {
    this.password = '';
    this.email = '';
    this.forgot = false;
  }
}

export interface LineLoginViewParams {
  hostWindow: window.Window;
  model: LineLoginViewModel;
  actions: LineLoginActions;
}

@Builder
function buildLineLogin(params: LineLoginViewParams) {
  LineLoginView({ params })
}

export const lineLoginBuilder: WrappedBuilder<[LineLoginViewParams]> = wrapBuilder(buildLineLogin);

@ComponentV2
struct LineLoginView {
  @Require @Once @Param params: LineLoginViewParams;
  @Local private insets: LineDialogInsets = { top: 0, right: 0, bottom: 0, left: 0 };
  @Local private keyboardHeight: number = 0;
  private readonly emailScroller: Scroller = new Scroller();
  private emailViewportHeight: number = 0;
  private focusedEmailField: number = -1;
  private active: boolean = false;
  private listening: boolean = false;
  private keyboardListening: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    this.params.model.dismissKeyboard = this.dismissKeyboard;
    this.updateInsets();
    try {
      this.updateKeyboardHeight(this.params.hostWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD)
        .bottomRect.height);
    } catch (_) { /* 初始键盘区域不可读时，等待高度事件。 */
    }
    try {
      this.params.hostWindow.on('avoidAreaChange', this.avoidAreaChanged);
      this.listening = true;
    } catch (_) { /* 部分窗口不支持监听，仍保留首次读取的真实避让区。 */
    }
    try {
      this.params.hostWindow.on('keyboardHeightChange', this.keyboardHeightChanged);
      this.keyboardListening = true;
    } catch (_) { /* 部分窗口不支持监听，仍保留首次读取的键盘区域。 */
    }
  }

  aboutToDisappear(): void {
    this.active = false;
    this.params.model.dismissKeyboard = undefined;
    this.focusedEmailField = -1;
    if (this.keyboardListening) {
      this.keyboardListening = false;
      try {
        this.params.hostWindow.off('keyboardHeightChange', this.keyboardHeightChanged);
      } catch (_) { /* 宿主窗口可能已经销毁，继续释放其他监听。 */
      }
    }
    if (this.listening) {
      this.listening = false;
      try {
        this.params.hostWindow.off('avoidAreaChange', this.avoidAreaChanged);
      } catch (_) { /* 宿主窗口可能已经销毁。 */
      }
    }
  }

  private readonly avoidAreaChanged: (event: window.AvoidAreaOptions) => void =
    (_event: window.AvoidAreaOptions): void => {
      if (this.active) {
        this.updateInsets();
      }
    };

  private updateInsets(): void {
    this.insets = readLineDialogInsets(this.params.hostWindow,
      (value: number): number => this.getUIContext().px2vp(value));
  }

  private readonly keyboardHeightChanged = (height: number): void => {
    if (this.active) {
      this.updateKeyboardHeight(height);
    }
  };

  private updateKeyboardHeight(height: number): void {
    this.keyboardHeight = Math.max(0, this.getUIContext().px2vp(height));
  }

  private readonly dismissKeyboard = (): boolean => {
    if (!this.active || this.keyboardHeight <= 0) {
      return false;
    }
    try {
      this.getUIContext().getFocusController().clearFocus();
    } catch (_) { /* 收起失败仍保留登录页，不把返回误判为取消登录。 */
    }
    // 等待真实高度事件确认收起，避免连续返回在键盘动画期间退出登录。
    return true;
  };

  private handleBack(): void {
    if (this.dismissKeyboard()) {
      return;
    }
    this.params.model.clearSecrets();
    if (this.params.model.state.method === 'email') {
      this.params.actions.showQr();
    } else {
      this.params.actions.cancel();
    }
  }

  private emailKeyboardInset(): number {
    // 只压缩邮箱 Scroll 的视口，扣除外层已经预留的底部空间，不改变 Dialog 尺寸。
    return this.params.model.state.method === 'email' ?
      Math.max(0, this.keyboardHeight - this.insets.bottom - LOGIN_BOTTOM_PADDING) : 0;
  }

  private updateEmailViewport(height: number): void {
    if (this.active) {
      this.emailViewportHeight = height;
      this.revealEmailField(this.focusedEmailField);
    }
  }

  private revealEmailField(index: number): void {
    if (!this.active || this.params.model.state.method !== 'email') {
      return;
    }
    this.focusedEmailField = index;
    if (index < 0 || this.emailViewportHeight <= 0) {
      return;
    }
    // 与下面输入框的固定布局共用尺寸；键盘动画引起视口变化时重新检查可见范围。
    const top = EMAIL_FORM_TOP + index * (EMAIL_INPUT_HEIGHT + EMAIL_INPUT_GAP);
    const bottom = top + EMAIL_INPUT_HEIGHT;
    try {
      const offset = this.emailScroller.currentOffset().yOffset;
      const target = top < offset ? top : Math.max(offset, bottom - this.emailViewportHeight);
      if (target !== offset) {
        this.emailScroller.scrollTo({ xOffset: 0, yOffset: target });
      }
    } catch (_) { /* Scroll 尚未挂载或已经卸载时不操作控制器。 */
    }
  }

  @Builder
  heading() {
    Text(this.params.model.state.method === 'qr' ? $r('app.string.mp_line_login_qr_title') :
      $r('app.string.mp_line_login_email_title'))
      .fontSize(30)
      .lineHeight(35)
      .fontWeight(FontWeight.Bold)
      .fontColor('#111111')
      .width('100%')
    Text(this.params.model.state.method === 'qr' ? $r('app.string.mp_line_login_qr_description') :
      $r('app.string.mp_line_login_email_description'))
      .fontSize(14).fontColor('#777777').margin({ top: 11 }).width('100%')
  }

  @Builder
  qrPage() {
    Column() {
      Blank()
      if (this.params.model.state.phase === 'qr' && this.params.model.state.qrUrl &&
        this.params.model.state.qrUrl.length <= 512) {
        QRCode(this.params.model.state.qrUrl).width(150).height(150)
        Text('00:' + (this.params.model.state.remainingSeconds ?? 0).toString().padStart(2, '0'))
          .fontSize(13).fontColor('#888888').margin({ top: 16 })
      } else if (this.params.model.state.phase === 'qr' && this.params.model.state.qrUrl &&
        this.params.model.state.qrUrl.length > 512) {
        Text($r('app.string.mp_line_login_qr_unavailable')).fontColor('#777777').textAlign(TextAlign.Center)
      }
      if (this.params.model.state.phase === 'qr' || this.params.model.state.phase === 'failed' ||
        this.params.model.state.phase === 'expired') {
        Button(this.params.model.state.phase === 'failed' ? $r('app.string.mp_line_login_retry') :
          $r('app.string.mp_line_login_refresh'))
          .height(32)
          .fontSize(13)
          .fontColor('#666666')
          .backgroundColor('#f0f1f2')
          .margin({ top: 12 })
          .enabled(this.params.model.state.phase !== 'qr' ||
            (this.params.model.state.qrUrl?.length ?? 0) > 512 || (this.params.model.state.remainingSeconds ?? 0) === 0)
          .onClick((): void => {
            if (this.params.model.state.phase === 'qr') {
              this.params.actions.showQr();
            } else {
              this.params.actions.retry();
            }
          })
      }
      Blank()
      Button($r('app.string.mp_line_login_email_title'))
        .width('100%')
        .height(48)
        .fontColor('#111111')
        .backgroundColor('#f0f1f2')
        .borderRadius(8)
        .onClick((): void => this.params.actions.showEmail())
    }.layoutWeight(1).width('100%')
  }

  @Builder
  emailPage() {
    Column() {
      Scroll(this.emailScroller) {
        this.emailForm()
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off).align(Alignment.TopStart)
      .onAreaChange((_oldArea: Area, area: Area): void => this.updateEmailViewport(Number(area.height)))
      this.emailActions()
    }.layoutWeight(1).width('100%').padding({ bottom: this.emailKeyboardInset() })
  }

  @Builder
  private emailForm() {
    Column() {
      TextInput({ placeholder: $r('app.string.mp_line_login_email_placeholder'), text: this.params.model.email })
        .type(InputType.Email)
        .cancelButton({ style: CancelButtonStyle.INPUT })
        .height(EMAIL_INPUT_HEIGHT)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .border({ width: { bottom: 1 }, color: '#dddddd' })
        .onChange((value: string): void => {
          this.params.model.email = value;
        })
        .onFocus((): void => this.revealEmailField(0))
        .onBlur((): void => { this.focusedEmailField = -1; })
      TextInput({ placeholder: $r('app.string.mp_line_login_password_placeholder'), text: this.params.model.password })
        .type(InputType.Password)
        .showPasswordIcon(true)
        .cancelButton({ style: CancelButtonStyle.INPUT })
        .height(EMAIL_INPUT_HEIGHT)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .borderRadius(0)
        .border({ width: { bottom: 1 }, color: '#dddddd' })
        .margin({ top: EMAIL_INPUT_GAP })
        .onChange((value: string): void => {
          this.params.model.password = value;
        })
        .onFocus((): void => this.revealEmailField(1))
        .onBlur((): void => { this.focusedEmailField = -1; })
    }.width('100%').padding({ top: EMAIL_FORM_TOP })
  }

  @Builder
  private emailActions() {
    // 操作区独立于表单滚动，在邮箱可用区域底部展示。
    Row() {
      Text($r('app.string.mp_line_login_forgot_password')).fontSize(14).fontColor('#666666')
        .onClick((): void => {
          this.params.model.forgot = true;
        })
      Blank()
      Button() {
        Image($r('app.media.mp_line_login_next'))
          .width(26)
          .height(26)
          .objectFit(ImageFit.Contain)
      }
      .width(56)
      .height(56)
      .padding(0)
      .borderRadius(28)
      .backgroundColor(
        this.params.model.email.length > 0 && this.params.model.password.length > 0 ? '#06c755' : '#f0f1f2')
      .enabled(this.params.model.email.length > 0 && this.params.model.password.length > 0 && !this.busy())
      .accessibilityText($r('app.string.mp_line_login_next'))
      .onClick((): void => {
        const email: string = this.params.model.email;
        const password: string = this.params.model.password;
        this.params.actions.submitEmail(email, password);
      })
    }.width('100%').margin({ top: 24 }).flexShrink(0)
  }

  @Builder
  private registrationAction() {
    Button($r('app.string.mp_line_registration_title'))
      .width('100%')
      .height(40)
      .fontSize(14)
      .fontColor('#06c755')
      .backgroundColor(Color.Transparent)
      .margin({ top: 12 })
      .enabled(!this.busy())
      .onClick((): void => {
        this.params.model.clearSecrets();
        this.params.actions.register?.();
      })
  }

  @Builder
  modal() {
    Column() {
      Column() {
        if (this.params.model.forgot) {
          Text($r('app.string.mp_line_login_forgot_password')).fontWeight(FontWeight.Bold)
          Text($r('app.string.mp_line_login_forgot_description')).margin({ top: 12 })
        } else if (this.params.model.state.phase === 'pin') {
          Text($r('app.string.mp_line_login_pin', this.params.model.state.pin ?? ''))
        } else if (this.params.model.state.phase === 'expired') {
          Text($r('app.string.mp_line_login_qr_expired', this.getUIContext()
            .getHostContext()?.resourceManager
            .getStringSync($r('app.string.mp_line_login_refresh')) ?? ''))
        } else {
          Text(this.errorText())
        }
        Button($r('app.string.mp_line_login_ok')).margin({ top: 24 }).fontColor('#06c755')
          .backgroundColor(Color.Transparent).onClick((): void => {
          this.params.model.forgot = false;
          this.params.model.dismissed = true;
        })
      }.width('85%').padding(24).backgroundColor(Color.White).borderRadius(16)
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#66000000')
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Row() {
          Button() {
            Image($r('app.media.mp_line_login_back'))
              .width(24)
              .height(24)
              .objectFit(ImageFit.Contain)
          }
          .width(40)
          .height(40)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.params.model.state.method === 'email' ? $r('app.string.mp_line_login_qr_title') :
            $r('app.string.mp_line_login_close'))
          .onClick((): void => this.handleBack())

          Blank()
        }.width('100%')

        Column() {
          this.heading()
        }.width('100%').margin({ top: 30 })

        if (this.params.model.state.method === 'qr') {
          this.qrPage()
        } else {
          this.emailPage()
        }
        this.registrationAction()
      }.width('100%').height('100%')
      .padding({ left: 24, right: 24, bottom: LOGIN_BOTTOM_PADDING }).backgroundColor(Color.White)

      if (this.busy()) {
        Stack({ alignContent: Alignment.TopStart }) {
          Column() {
            LoadingProgress().width(40).height(40)
          }
          .width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#44000000')

          Button() {
            Image($r('app.media.mp_line_login_back'))
              .width(24)
              .height(24)
              .objectFit(ImageFit.Contain)
          }
          .width(40)
          .height(40)
          .padding(0)
          .margin({ left: 24 })
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.params.model.state.method === 'email' ? $r('app.string.mp_line_login_qr_title') :
            $r('app.string.mp_line_login_close'))
          .onClick((): void => this.handleBack())
        }.width('100%').height('100%')
      }
      if (this.params.model.forgot || (!this.params.model.dismissed &&
        (this.params.model.state.phase === 'pin' || this.params.model.state.phase === 'failed' ||
          this.params.model.state.phase === 'expired'))) {
        this.modal()
      }
    // 外层保持全屏，邮箱在自己的滚动区避让，扫码页不跟随键盘调整。
    }.width('100%').height('100%')
    .padding(this.insets).backgroundColor(Color.White)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM,
      SafeAreaEdge.START, SafeAreaEdge.END])
  }

  private busy(): boolean {
    const phase = this.params.model.state.phase;
    return phase === 'loading' || phase === 'confirming' || (phase === 'pin' && this.params.model.dismissed);
  }

  private errorText(): Resource {
    const code: string = this.params.model.state.errorCode ?? '';
    if (code === LineErrorCode.RPC_NETWORK_FAILED || code === LineErrorCode.RPC_TIMEOUT) {
      return $r('app.string.mp_line_login_network_error');
    }
    if (code === LineErrorCode.EMAIL_VERIFICATION_TIMEOUT) {
      return $r('app.string.mp_line_login_pin_expired');
    }
    if (code === LineErrorCode.qrService(LineServiceErrorCode.QR_NOT_ALLOWED_SECONDARY_DEVICE) ||
      code === LineErrorCode.emailService(LineServiceErrorCode.EMAIL_NOT_ALLOWED_SECONDARY_DEVICE)) {
      return $r('app.string.mp_line_login_not_allowed');
    }
    if (code === LineErrorCode.emailService(LineServiceErrorCode.EMAIL_INVALID_IDENTITY_CREDENTIAL)) {
      return $r('app.string.mp_line_login_invalid_info');
    }
    if (code === LineErrorCode.EMAIL_INVALID_ARGUMENT) {
      return $r('app.string.mp_line_login_enter_credentials');
    }
    return $r('app.string.mp_line_login_unknown_error');
  }
}

