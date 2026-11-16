import { window } from '@kit.ArkUI';
import { LineRegistrationViewModel } from './LineRegistrationViewModel';
import { LineDialogInsets, readLineDialogInsets } from '../../LineDialogInsets';
import { LinePhoneVerificationMethod } from '../LineRegistrationTypes';

export interface LineRegistrationViewParams { hostWindow: window.Window; model: LineRegistrationViewModel; back: () => void; }
@Builder
function buildLineRegistration(params: LineRegistrationViewParams) { LineRegistrationView({ params }) }
export const lineRegistrationBuilder: WrappedBuilder<[LineRegistrationViewParams]> = wrapBuilder(buildLineRegistration);

@ComponentV2
struct LineRegistrationView {
  @Require @Once @Param params: LineRegistrationViewParams;
  @Local private insets: LineDialogInsets = { top: 0, right: 0, bottom: 0, left: 0 };
  @Local private keyboard: number = 0;
  private timer: number = -1;
  private active: boolean = false;
  private listening: boolean = false;
  private keyboardListening: boolean = false;
  private readonly scroller: Scroller = new Scroller();
  aboutToAppear(): void {
    this.active = true;
    this.params.model.dismissKeyboard = this.dismissKeyboard;
    this.updateInsets();
    try { this.heightChanged(this.params.hostWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD).bottomRect.height); } catch (_) {}
    try { this.params.hostWindow.on('avoidAreaChange', this.changed); this.listening = true; } catch (_) {}
    try { this.params.hostWindow.on('keyboardHeightChange', this.heightChanged); this.keyboardListening = true; } catch (_) {}
    this.timer = setInterval((): void => { if (this.active) { this.params.model.refresh(); } }, 1000);
  }
  aboutToDisappear(): void {
    this.active = false; this.params.model.dismissKeyboard = undefined; this.params.model.clearSecrets();
    if (this.timer !== -1) { clearInterval(this.timer); this.timer = -1; }
    if (this.listening) { try { this.params.hostWindow.off('avoidAreaChange', this.changed); } catch (_) {} }
    if (this.keyboardListening) { try { this.params.hostWindow.off('keyboardHeightChange', this.heightChanged); } catch (_) {} }
  }
  private readonly changed = (_event: window.AvoidAreaOptions): void => { if (this.active) { this.updateInsets(); } };
  private readonly heightChanged = (height: number): void => { if (this.active) { this.keyboard = Math.max(0, this.getUIContext().px2vp(height)); } };
  private updateInsets(): void { this.insets = readLineDialogInsets(this.params.hostWindow, (n: number): number => this.getUIContext().px2vp(n)); }
  private readonly dismissKeyboard = (): boolean => {
    if (!this.active || this.keyboard <= 0) { return false; }
    try { this.getUIContext().getFocusController().clearFocus(); } catch (_) {}
    return true;
  };
  private back(): void { if (!this.dismissKeyboard()) { this.params.model.clearSecrets(); this.params.back(); } }
  private available(method: LinePhoneVerificationMethod): boolean { return this.params.model.state.availableMethods?.includes(method) ?? false; }

  @Builder
  countryAndPhone() {
    Text($r('app.string.mp_line_registration_country')).fontSize(16)
    Select(this.params.model.countries.map((country): SelectOption => ({ value: country.label })))
      .selected(this.params.model.countryIndex).enabled(!this.params.model.state.busy)
      .onSelect((index: number): void => this.params.model.selectCountry(index))
    if (this.params.model.countries.length === 0) { Text($r('app.string.mp_line_registration_country_unavailable')) }
    if (this.params.model.state.stage === 'phoneInput') {
      TextInput({ placeholder: $r('app.string.mp_line_registration_phone'), text: this.params.model.phone })
        .type(InputType.PhoneNumber).onChange((value: string): void => { this.params.model.phone = value; })
      Text($r('app.string.mp_line_registration_phone_terms'))
      Row({ space: 12 }) {
        Button($r('app.string.mp_line_registration_terms')).onClick((): void => { this.params.model.publicPolicy(true); })
        Button($r('app.string.mp_line_registration_privacy')).onClick((): void => { this.params.model.publicPolicy(false); })
      }
      Button($r('app.string.mp_line_registration_next')).enabled(!this.params.model.state.busy && this.params.model.phone.length > 0)
        .onClick((): void => { this.params.model.perform((session): Promise<void> => session.submitPhoneNumber(this.params.model.phone)); })
    }
  }
  @Builder
  verification() {
    Text(this.params.model.state.prettifiedPhoneNumber ?? '')
    if (this.available(LinePhoneVerificationMethod.SMS)) {
      Button($r('app.string.mp_line_registration_sms')).enabled(!this.params.model.state.busy && (this.params.model.state.resendRemainingMs ?? 0) === 0)
        .onClick((): void => { this.params.model.perform((session): Promise<void> => session.requestVerification(LinePhoneVerificationMethod.SMS)); })
    }
    if ((this.params.model.state.resendRemainingMs ?? 0) > 0) {
      Text($r('app.string.mp_line_registration_cooldown', Math.ceil((this.params.model.state.resendRemainingMs ?? 0) / 1000)))
    }
    if (this.available(LinePhoneVerificationMethod.IVR)) {
      Text($r('app.string.mp_line_registration_ivr_description'))
      Button($r('app.string.mp_line_registration_ivr')).enabled(!this.params.model.state.busy)
        .onClick((): void => { this.params.model.perform((session): Promise<void> => session.requestVerification(LinePhoneVerificationMethod.IVR)); })
    }
    if (this.available(LinePhoneVerificationMethod.SMSPULL)) {
      Button($r('app.string.mp_line_registration_pull')).enabled(!this.params.model.state.busy)
        .onClick((): void => { this.params.model.perform((session): Promise<void> => session.startPullSms()); })
    }
    if (this.params.model.state.destinationPhoneNumber) {
      Text($r('app.string.mp_line_registration_pull_instructions'))
      Text(this.params.model.state.destinationPhoneNumber ?? '').copyOption(CopyOptions.LocalDevice)
      Text(this.params.model.state.pinCodeMessage ?? '').copyOption(CopyOptions.LocalDevice)
    } else {
      TextInput({ placeholder: $r('app.string.mp_line_registration_code'), text: this.params.model.code })
        .type(InputType.Number).onChange((value: string): void => { this.params.model.code = value; })
      Button($r('app.string.mp_line_registration_next')).enabled(!this.params.model.state.busy && this.params.model.code.length > 0)
        .onClick((): void => this.params.model.submitCode())
    }
  }
  @Builder
  form() {
    if (this.params.model.state.stage === 'countrySelection' || this.params.model.state.stage === 'phoneInput') {
      this.countryAndPhone()
    } else if (this.params.model.state.stage === 'verification') {
      this.verification()
    } else if (this.params.model.state.stage === 'profileInput') {
      TextInput({ placeholder: $r('app.string.mp_line_registration_name'), text: this.params.model.name })
        .onChange((value: string): void => { this.params.model.name = value; })
      Button($r('app.string.mp_line_registration_next')).enabled(!this.params.model.state.busy && this.params.model.name.length > 0)
        .onClick((): void => { this.params.model.perform((session): Promise<void> => session.validateProfile(this.params.model.name)); })
    } else if (this.params.model.state.stage === 'passwordInput') {
      TextInput({ placeholder: $r('app.string.mp_line_registration_password'), text: this.params.model.password })
        .type(InputType.Password).showPasswordIcon(true).onChange((value: string): void => { this.params.model.password = value; })
      Text($r('app.string.mp_line_registration_create_notice'))
      Button($r('app.string.mp_line_registration_create')).enabled(!this.params.model.state.busy && this.params.model.password.length > 0)
        .onClick((): void => this.params.model.submitPassword())
    } else if (this.params.model.state.stage === 'privacySettings') {
      Text($r('app.string.mp_line_registration_pending'))
      Row() {
        Checkbox().select(this.params.model.autoAdd).onChange((value: boolean): void => { this.params.model.autoAdd = value; })
        Text($r('app.string.mp_line_registration_auto_add')).layoutWeight(1)
      }
      Row() {
        Checkbox().select(this.params.model.searchable).onChange((value: boolean): void => { this.params.model.searchable = value; })
        Text($r('app.string.mp_line_registration_searchable')).layoutWeight(1)
      }
      Button($r('app.string.mp_line_registration_next')).enabled(!this.params.model.state.busy)
        .onClick((): void => { this.params.model.perform((session): Promise<void> => session.submitPrivacy({ privacySyncContacts: this.params.model.autoAdd, privacySearchByPhoneNumber: this.params.model.searchable })); })
    } else if (this.params.model.state.stage === 'ageVerification') {
      Text($r('app.string.mp_line_registration_age'))
      Button($r('app.string.mp_line_registration_skip')).enabled(!this.params.model.state.busy)
        .onClick((): void => { this.params.model.perform((session): Promise<void> => session.skipAgeVerification()); })
    } else if (this.params.model.state.stage === 'challengeRequired') {
      Text($r('app.string.mp_line_registration_challenge'))
      Button($r('app.string.mp_line_registration_review')).enabled(!this.params.model.state.busy).onClick((): void => this.params.model.challenge())
    } else if (this.params.model.state.stage === 'agreementRequired') {
      Text($r('app.string.mp_line_registration_pending'))
      Button($r('app.string.mp_line_registration_review')).enabled(!this.params.model.state.busy).onClick((): void => this.params.model.agreement())
    } else if (this.params.model.state.stage === 'creationUncertain') {
      Text($r('app.string.mp_line_registration_uncertain'))
    } else if (this.params.model.state.stage === 'initializing' && !this.params.model.state.busy) {
      Button($r('app.string.mp_line_registration_retry')).onClick((): void => { this.params.model.perform((session): Promise<void> => session.retryInitialization()); })
    } else if (this.params.model.state.stage === 'finalizing' && !this.params.model.state.busy) {
      Text($r('app.string.mp_line_registration_pending'))
      Button($r('app.string.mp_line_registration_retry')).onClick((): void => { this.params.model.perform((session): Promise<void> => session.resumeFinalization()); })
    }
  }
  build() {
    Column() {
      Row() {
        Button($r('app.string.mp_line_registration_back')).onClick((): void => this.back())
        Text($r('app.string.mp_line_registration_title')).fontSize(22).fontWeight(FontWeight.Bold).layoutWeight(1)
      }.width('100%').padding({ bottom: 20 })
      Scroll(this.scroller) {
        Column({ space: 20 }) {
          this.form()
          if (this.params.model.retryAfterChallenge) { Text($r('app.string.mp_line_registration_retry_action')) }
          if (this.params.model.error || this.params.model.state.errorCode) { Text(this.params.model.errorMessage()) }
          if (this.params.model.state.busy) { LoadingProgress().width(40).height(40) }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.TopStart)
    }.padding({ top: this.insets.top + 16, bottom: Math.max(this.insets.bottom, this.keyboard) + 16, left: this.insets.left + 24, right: this.insets.right + 24 })
    .width('100%').height('100%').backgroundColor(Color.White)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM, SafeAreaEdge.START, SafeAreaEdge.END])
  }
}
