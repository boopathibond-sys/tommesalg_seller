/// Centralised string-key catalogue — every translatable string in the app
/// has a constant here, and the matching value lives in
/// `assets/translations/<code>.json`.
///
/// Using constants instead of magic strings means:
///   * Renaming a key is a refactor, not a search-and-replace.
///   * The IDE auto-completes available keys.
///   * Stale keys can be detected with a static analyser.
///
/// ### Usage
/// ```dart
/// Text(TKeys.loginTitle.tr);
/// Text(TKeys.liveLabel.trParams({'viewers': '2.4K'}));
/// ```
abstract class TKeys {
  TKeys._();

  // ── General / brand ─────────────────────────────────────────────────────
  static const appName      = 'app_name';
  static const tagline      = 'tagline';
  static const loading      = 'loading';
  static const cancel       = 'cancel';
  static const ok           = 'ok';
  static const continueText = 'continue';
  static const retry        = 'retry';
  static const back         = 'back';
  static const required     = 'required';
  static const optional     = 'optional';

  // ── Splash ──────────────────────────────────────────────────────────────
  static const splashLoading = 'splash_loading';

  // ── Auth: login ─────────────────────────────────────────────────────────
  static const loginTitle           = 'login_title';
  static const loginSubtitle        = 'login_subtitle';
  static const loginCta             = 'login_cta';
  static const loginEmailLabel      = 'login_email_label';
  static const loginEmailHint       = 'login_email_hint';
  static const loginPasswordLabel   = 'login_password_label';
  static const loginPasswordHint    = 'login_password_hint';
  static const loginForgotPassword  = 'login_forgot_password';
  static const loginVipps           = 'login_vipps';
  static const loginGoogle          = 'login_google';
  static const loginNoAccount       = 'login_no_account';
  static const loginSignUp          = 'login_sign_up';
  static const loginOrContinueWith  = 'login_or_continue_with';

  // ── Auth: e-mail code ──────────────────────────────────────────────────
  static const emailCodeMembersOnly    = 'email_code_members_only';
  static const emailCodeNoAccount      = 'email_code_no_account';
  static const emailCodeSendCta        = 'email_code_send_cta';
  static const emailCodeWillSend       = 'email_code_will_send';
  static const emailCodeSent           = 'email_code_sent';
  static const emailCodeNewSent        = 'email_code_new_sent';
  static const emailCodeVerifyTitle    = 'email_code_verify_title';
  static const emailCodeVerifySubtitle = 'email_code_verify_subtitle';
  static const emailCodeVerifyCta      = 'email_code_verify_cta';
  static const emailCodeLabel          = 'email_code_label';
  static const emailCodeHint           = 'email_code_hint';
  static const emailCodeResend         = 'email_code_resend';
  static const emailCodeChangeEmail    = 'email_code_change_email';
  static const emailCodeEnterCode      = 'email_code_enter_code';

  // ── Auth: register ─────────────────────────────────────────────────────
  static const registerTitle            = 'register_title';
  static const registerSubtitle         = 'register_subtitle';
  static const registerNameLabel        = 'register_name_label';
  static const registerNameHint         = 'register_name_hint';
  static const registerEmailHint        = 'register_email_hint';
  static const registerPhoneLabel       = 'register_phone_label';
  static const registerPasswordHelper   = 'register_password_helper';
  static const registerBirthLabel       = 'register_birth_label';
  static const registerGenderLabel      = 'register_gender_label';
  static const registerGenderHint       = 'register_gender_hint';
  static const registerGenderSheetTitle = 'register_gender_sheet_title';
  static const registerCta              = 'register_cta';
  static const registerVipps            = 'register_vipps';
  static const registerGoogle           = 'register_google';
  static const registerHaveAccount      = 'register_have_account';
  static const registerLoginNow         = 'register_login_now';
  static const registerCheckEmail       = 'register_check_email';
  static const genderMale               = 'gender_male';
  static const genderFemale             = 'gender_female';
  static const genderOther              = 'gender_other';

  // ── Validation / errors ────────────────────────────────────────────────
  static const validationEmailPasswordRequired = 'validation_email_password_required';
  static const validationEmailRequired         = 'validation_email_required';
  static const errorGeneric                    = 'error_generic';

  // ── Bottom nav ─────────────────────────────────────────────────────────
  static const tabHome      = 'tab_home';
  static const tabExplore   = 'tab_explore';
  static const tabSellers   = 'tab_sellers';
  static const tabMessages  = 'tab_messages';
  static const tabAccount   = 'tab_account';

  // ── Home top bar ───────────────────────────────────────────────────────
  static const homeSearchHint = 'home_search_hint';

  // ── Categories ─────────────────────────────────────────────────────────
  static const catForYou      = 'cat_for_you';
  static const catSneakers    = 'cat_sneakers';
  static const catFurniture   = 'cat_furniture';
  static const catPokemon     = 'cat_pokemon';
  static const catFashion     = 'cat_fashion';
  static const catTech        = 'cat_tech';
  static const catBooks       = 'cat_books';
  static const catOutdoor     = 'cat_outdoor';
  static const catClothes     = 'cat_clothes';
  static const catElectronics = 'cat_electronics';
  static const catHome        = 'cat_home';
  static const catSports      = 'cat_sports';
  static const catGarden      = 'cat_garden';
  static const catOther       = 'cat_other';

  // ── Live ───────────────────────────────────────────────────────────────
  static const liveLabel      = 'live_label';
  static const startBidSuffix = 'start_bid_suffix';

  // ── Discover ───────────────────────────────────────────────────────────
  static const discoverTitle    = 'discover_title';
  static const discoverSubtitle = 'discover_subtitle';

  // ── Empty states ───────────────────────────────────────────────────────
  static const sellersEmptyTitle  = 'sellers_empty_title';
  static const sellersEmptyBody   = 'sellers_empty_body';
  static const messagesEmptyTitle = 'messages_empty_title';
  static const messagesEmptyBody  = 'messages_empty_body';

  // ── Account ────────────────────────────────────────────────────────────
  static const accountTitle          = 'account_title';
  static const accountWelcome        = 'account_welcome';
  static const accountMyPurchases    = 'account_my_purchases';
  static const accountAddresses      = 'account_addresses';
  static const accountPaymentMethods = 'account_payment_methods';
  static const accountNotifications  = 'account_notifications';
  static const accountHelp           = 'account_help';
  static const accountLanguage       = 'account_language';
  static const accountLogout         = 'account_logout';

  // ── Profile sections ───────────────────────────────────────────────────
  // Names dropped the `profile_` prefix per product. Snake-case is kept in
  // the JSON keys themselves; users only ever see the resolved value.
  static const deliveryAddresses    = 'delivery';
  static const deliverySubtitle     = 'delivery sub';
  static const billingAddresses     = 'billing';
  static const billingSubtitle      = 'billing sub';
  static const paymentSection       = 'payment';
  static const paymentSubtitle      = 'payment sub';
  static const shippingSection      = 'shipping';
  static const shippingSubtitle     = 'shipping sub';
  static const change               = 'change';
  static const viewAll              = 'view all';
  static const update               = 'update';
  static const editProfileTitle     = 'edit profile title';
  static const editProfileSubtitle  = 'edit profile subtitle';
  static const nicknameLabel        = 'nickname label';
  static const nicknameHint         = 'nickname hint';
  static const useNicknamePublic    = 'use nickname public';
  static const useNicknamePublicDesc = 'use nickname public desc';
  static const profileUpdated       = 'profile updated';
  static const primary              = 'primary';
  static const noAddressAdded       = 'no address added';
  static const addAddress           = 'add address';
  static const addressesTitle       = 'addresses title';
  static const addNewAddress        = 'add new address';
  static const makeDefault          = 'make default';
  static const editAction           = 'edit action';
  static const deleteAction         = 'delete action';
  static const noAddressesYet       = 'no addresses yet';
  static const deleteAddressTitle   = 'delete address title';
  static const deleteAddressBody    = 'delete address body';
  static const addressName          = 'address name';
  static const addressNameHint      = 'address name hint';
  static const addressStreet        = 'address street';
  static const addressStreetHint    = 'address street hint';
  static const addressPostal        = 'address postal';
  static const addressPostalHint    = 'address postal hint';
  static const addressCity          = 'address city';
  static const addressCityHint      = 'address city hint';
  static const addressCountry       = 'address country';
  static const addressCountryHint   = 'address country hint';
  static const addressPhone         = 'address phone';
  static const addressPhoneHint     = 'address phone hint';
  static const setAsDefault         = 'set as default';
  static const save                 = 'save';
  static const addressAdded         = 'address added';
  static const editAddressTitle     = 'edit address title';
  static const addressUpdated       = 'address updated';
  static const homeDelivery         = 'home delivery';
  static const homeDeliveryDesc     = 'home delivery desc';
  static const pickupYourself       = 'pick up';
  static const pickupYourselfDesc   = 'pick up desc';
  static const addressHome          = 'address home';
  static const addressWork          = 'address work';
  static const cardExpiry           = 'card expiry';

  // ── Payment methods list ──────────────────────────────────────────
  static const paymentMethodsTitle  = 'payment methods title';
  static const addNewCard           = 'add new card';
  static const noPaymentMethodsYet  = 'no payment methods yet';
  static const deletePaymentTitle   = 'delete payment title';
  static const deletePaymentBody    = 'delete payment body';
  static const paymentDeleted       = 'payment deleted';
  static const addCardComingSoon    = 'add card coming soon';
  /// Snackbar shown after Stripe's PaymentSheet confirms a SetupIntent
  /// successfully and the backend has attached the new card.
  static const cardAdded            = 'card added';

  // ── Language picker ────────────────────────────────────────────────────
  static const languageSheetTitle = 'language_sheet_title';
  static const languageEnglish    = 'language_english';
  static const languageNorwegian  = 'language_norwegian';

  // ── Todo (dev screen) ──────────────────────────────────────────────────
  static const todoTitle          = 'todo_title';
  static const todoEmpty          = 'todo_empty';
  static const todoSomethingWrong = 'todo_something_wrong';
  static const todoNew            = 'todo_new';
  static const todoHint           = 'todo_hint';
  static const todoAdd            = 'todo_add';
  static const todoCancel         = 'todo_cancel';
  static const shop         = 'shop';
  static const store         = 'Store';
  static const myOrders         = 'my_orders';
  static const defaultText         = 'default';
  static const totalProducts         = 'Total Products';
  static const products         = 'Products';
}
