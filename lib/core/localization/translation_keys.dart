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

  // ── Account deletion (App Review guideline 5.1.1(v)) ───────────────────
  // An app that lets a user create an account has to let them delete it from
  // inside the app. The seller never taps a delete API here — the entry point
  // hands off to the web confirmation page (see ProfileController
  // .requestAccountDeletionHandoff) — but the *entry point* must live in the
  // app and be easy to find, which is what these strings label.
  static const accountDelete         = 'account_delete';
  static const accountDeleteSubtitle = 'account_delete_subtitle';
  static const accountDeleteTitle    = 'account_delete_title';
  static const accountDeleteMessage  = 'account_delete_message';
  static const accountDeleteContinue = 'account_delete_continue';
  static const accountDeleteFailed   = 'account_delete_failed';

  // ── Legal + support ────────────────────────────────────────────────────
  // Guideline 1.2 wants the terms a UGC app's users agreed to and a way to
  // reach a human to be reachable from inside the app; 5.1.1 wants the
  // privacy policy. These label those three rows.
  static const legalTerms            = 'legal_terms';
  static const legalTermsSubtitle    = 'legal_terms_subtitle';
  static const legalPrivacy          = 'legal_privacy';
  static const legalPrivacySubtitle  = 'legal_privacy_subtitle';
  static const legalSupport          = 'legal_support';
  static const legalSupportSubtitle  = 'legal_support_subtitle';
  static const legalOpenFailedTitle  = 'legal_open_failed_title';
  static const legalOpenFailed       = 'legal_open_failed';

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
  static const myOrders         = 'my_orders';
  static const defaultText         = 'default';

  // ── Session / auth errors ──
  static const accessDeniedTitle = 'access_denied_title';
  static const accessDeniedBody = 'access_denied_body';

  // ── Bottom navigation ──
  static const navHome = 'nav_home';
  static const navStreams = 'nav_streams';
  static const navProducts = 'nav_products';
  static const navStock = 'nav_stock';
  static const navProfile = 'nav_profile';

  // ── Common actions & labels ──
  static const tryAgain = 'try_again';
  static const stay = 'stay';
  static const edit = 'edit';
  static const yes = 'yes';
  static const no = 'no';
  static const typeLabel = 'type_label';
  static const statusLabel = 'status_label';
  static const activeLabel = 'active_label';
  static const verifiedLabel = 'verified_label';
  static const emailLabel = 'email_label';
  static const phoneLabel = 'phone_label';
  static const errorTitle = 'error_title';
  static const updatedTitle = 'updated_title';
  static const productsLabel = 'products_label';
  static const ordersLabel = 'orders_label';

  // ── Home tab ──
  static const exitTitle = 'exit_title';
  static const exitBody = 'exit_body';
  static const exitConfirm = 'exit_confirm';
  static const sellerLabel = 'seller_label';
  static const welcomeBack = 'welcome_back';
  static const readyToSell = 'ready_to_sell';
  static const readyToSellBody = 'ready_to_sell_body';
  static const createShipment = 'create_shipment';
  static const myStreams = 'my_streams';
  static const liveNow = 'live_now';
  static const planned = 'planned';
  static const followers = 'followers';
  static const quickActions = 'quick_actions';
  static const quickActionsSub = 'quick_actions_sub';
  static const seeProducts = 'see_products';
  static const seeProductsSub = 'see_products_sub';
  static const configureStreams = 'configure_streams';
  static const configureStreamsSub = 'configure_streams_sub';
  static const createNewSku = 'create_new_sku';
  static const createNewSkuSub = 'create_new_sku_sub';
  static const editExistingSku = 'edit_existing_sku';
  static const editExistingSkuSub = 'edit_existing_sku_sub';
  static const ordersSub = 'orders_sub';

  // ── Dashboard ──
  static const dashboardTitle = 'dashboard_title';
  static const dashboardSub = 'dashboard_sub';
  static const availableInStore = 'available_in_store';
  static const shipmentsLabel = 'shipments_label';
  static const liveLower = 'live_lower';
  static const plannedLower = 'planned_lower';
  static const inMonth = 'in_month';
  static const completedPayments = 'completed_payments';
  static const turnoverLabel = 'turnover_label';
  static const paidSalesVolume = 'paid_sales_volume';
  static const auctionCommission = 'auction_commission';
  static const postedByAdmin = 'posted_by_admin';
  static const biddingCommittee = 'bidding_committee';
  static const noDashboardData = 'no_dashboard_data';
  static const selectMonth = 'select_month';
  static const periodLabel = 'period_label';
  static const streamAnalyticsCaps = 'stream_analytics_caps';
  static const averageDuration = 'average_duration';
  static const minutesUnit = 'minutes_unit';
  static const averageViewers = 'average_viewers';
  static const perStreamUnit = 'per_stream_unit';
  static const productStatusCaps = 'product_status_caps';
  static const soldLower = 'sold_lower';
  static const availableLabel = 'available_label';
  static const productUnitSingular = 'product_unit_singular';
  static const productUnitPlural = 'product_unit_plural';
  static const soldLabel = 'sold_label';
  static const thisMonthLower = 'this_month_lower';

  // ── Feature highlights & profile tab ──
  static const goLive = 'go_live';
  static const goLiveSub = 'go_live_sub';
  static const planYourStreams = 'plan_your_streams';
  static const planYourStreamsSub = 'plan_your_streams_sub';
  static const manageYourStock = 'manage_your_stock';
  static const manageYourStockSub = 'manage_your_stock_sub';
  static const buildYourCatalog = 'build_your_catalog';
  static const buildYourCatalogSub = 'build_your_catalog_sub';
  static const whatYouCanDo = 'what_you_can_do';
  static const whatYouCanDoSub = 'what_you_can_do_sub';
  static const aboutSellerSquad = 'about_seller_squad';
  static const aboutSellerSquadBody = 'about_seller_squad_body';
  static const couldNotLoadHome = 'could_not_load_home';
  static const couldNotLoadProfile = 'could_not_load_profile';
  static const contactInformation = 'contact_information';
  static const aboutTheStore = 'about_the_store';
  static const seeAllOrders = 'see_all_orders';
  static const activeAccount = 'active_account';
  static const profilePhoto = 'profile_photo';
  static const coverPhoto = 'cover_photo';
  static const profileCardThumbnail = 'profile_card_thumbnail';
  static const imageUploaded = 'image_uploaded';
  static const couldNotUploadImage = 'could_not_upload_image';
  static const addCoverPhoto = 'add_cover_photo';
  static const addThumbnail = 'add_thumbnail';
  static const websiteLabel = 'website_label';
  static const socialLinksLabel = 'social_links_label';
  static const logOutTitle = 'log_out_title';
  static const logOutBody = 'log_out_body';
  static const logOut = 'log_out';

  // ── Auth ──
  static const splashTagline = 'splash_tagline';
  static const authEnterEmailPassword = 'auth_enter_email_password';
  static const authLoginFailed = 'auth_login_failed';
  static const authEnterEmail = 'auth_enter_email';
  static const authCodeSendFailed = 'auth_code_send_failed';
  static const authLogIn = 'auth_log_in';
  static const authSendLoginCode = 'auth_send_login_code';
  static const authWelcomeBackStore = 'auth_welcome_back_store';
  static const authForgotPassword = 'auth_forgot_password';
  static const authCodeByEmail = 'auth_code_by_email';
  static const authStaySignedIn = 'auth_stay_signed_in';
  static const authBusinessOnly = 'auth_business_only';
  static const authNotSellerYet = 'auth_not_seller_yet';
  static const authBecomeSeller = 'auth_become_seller';
  static const authBecomeSellerSub = 'auth_become_seller_sub';
  static const authPassword = 'auth_password';
  static const authEmailCode = 'auth_email_code';
  static const authSomethingWrong = 'auth_something_wrong';
  static const authForgotPasswordTitle = 'auth_forgot_password_title';
  static const authForgotPasswordBody = 'auth_forgot_password_body';
  static const authSendResetLink = 'auth_send_reset_link';
  static const authPasswordTooShort = 'auth_password_too_short';
  static const authPasswordsDoNotMatch = 'auth_passwords_do_not_match';
  static const authPasswordUpdateFailed = 'auth_password_update_failed';
  static const authPasswordUpdated = 'auth_password_updated';
  static const authSetNewPassword = 'auth_set_new_password';
  static const authSetNewPasswordBody = 'auth_set_new_password_body';
  static const authNewPasswordCaps = 'auth_new_password_caps';
  static const authConfirmPasswordCaps = 'auth_confirm_password_caps';
  static const authUpdatePassword = 'auth_update_password';
  static const authResetLinkSent = 'auth_reset_link_sent';

  // ── Auth: code verification & gate ──
  static const verifyCodeTitle = 'verify_code_title';
  static const verifyEnterCode = 'verify_enter_code';
  static const verifyFailed = 'verify_failed';
  static const verifyResendFailed = 'verify_resend_failed';
  static const verifyNewCodeSent = 'verify_new_code_sent';
  static const verifySentTo = 'verify_sent_to';
  static const verifyLoginCodeCaps = 'verify_login_code_caps';
  static const verifySixDigitHint = 'verify_six_digit_hint';
  static const verifyResendIn = 'verify_resend_in';
  static const verifyResendCode = 'verify_resend_code';
  static const verifyChangeEmail = 'verify_change_email';
  static const applicantCodeSendFailed = 'applicant_code_send_failed';
  static const applicantConfirmEmail = 'applicant_confirm_email';
  static const applicantConfirmBody = 'applicant_confirm_body';
  static const applicantCheckTitle = 'applicant_check_title';
  static const applicantCheckBody = 'applicant_check_body';
  static const applicantSendCode = 'applicant_send_code';
  static const applicantUseAppliedEmail = 'applicant_use_applied_email';
  static const gateVerifyFailed = 'gate_verify_failed';
  static const gateNoSellerAccess = 'gate_no_seller_access';
  static const gateNoSellerAccessBody = 'gate_no_seller_access_body';

  // ── Products: manage & scan ──
  static const successTitle = 'success_title';
  static const cancelAction = 'cancel_action';
  static const removeAction = 'remove_action';
  static const sendAction = 'send_action';
  static const deleteAction2 = 'delete_action_2';
  static const refreshAction = 'refresh_action';
  static const noSchedule = 'no_schedule';
  static const enterUpc = 'enter_upc';
  static const couldNotAddProduct = 'could_not_add_product';
  static const enterProductName = 'enter_product_name';
  static const productAdded = 'product_added';
  static const nothingToSend = 'nothing_to_send';
  static const awaitingApproval = 'awaiting_approval';
  static const addProductFirst = 'add_product_first';
  static const sendToQueueTitle = 'send_to_queue_title';
  static const sendToQueueBody = 'send_to_queue_body';
  static const sendToQueueBodySkipped = 'send_to_queue_body_skipped';
  static const productIs = 'product_is';
  static const productsAre = 'products_are';
  static const couldNotSendProducts = 'could_not_send_products';
  static const pleaseTryAgain = 'please_try_again';
  static const sentToQueue = 'sent_to_queue';
  static const queuedFor = 'queued_for';
  static const queuedForSkipped = 'queued_for_skipped';
  static const removeProductTitle = 'remove_product_title';
  static const removeProductBody = 'remove_product_body';
  static const removedTitle = 'removed_title';
  static const removedFromStream = 'removed_from_stream';
  static const couldNotDeleteProduct = 'could_not_delete_product';
  static const assignToLive = 'assign_to_live';
  static const myProducts = 'my_products';
  static const noScheduledStreams = 'no_scheduled_streams';
  static const selectStream = 'select_stream';
  static const productNotFound = 'product_not_found';
  static const enterDetailsToAdd = 'enter_details_to_add';
  static const scanAgain = 'scan_again';
  static const productNameLabel = 'product_name_label';
  static const enterNameHint = 'enter_name_hint';
  static const addImage = 'add_image';
  static const addUnknownProduct = 'add_unknown_product';
  static const noProductsAddedYet = 'no_products_added_yet';
  static const submitQueueNote = 'submit_queue_note';
  static const sendToQueueCta = 'send_to_queue_cta';
  static const sendToQueueCtaCount = 'send_to_queue_cta_count';
  static const couldNotLoadStreams = 'could_not_load_streams';
  static const noStreamsYet = 'no_streams_yet';
  static const newStream = 'new_stream';
  static const quickView = 'quick_view';
  static const noDescription = 'no_description';
  static const cameraSource = 'camera_source';
  static const gallerySource = 'gallery_source';
  static const unsupportedFile = 'unsupported_file';
  static const onlyImageTypes = 'only_image_types';
  static const sizeLabel = 'size_label';
  static const colorLabel = 'color_label';
  static const pictureLabel = 'picture_label';
  static const otherLabel = 'other_label';
  static const describeDiscrepancyError = 'describe_discrepancy_error';
  static const reportUpdated = 'report_updated';
  static const couldNotUpdateReport = 'could_not_update_report';
  static const colorColon = 'color_colon';
  static const sizesColon = 'sizes_colon';
  static const reportDiscrepancyCaps = 'report_discrepancy_caps';
  static const reportDiscrepancyBody = 'report_discrepancy_body';
  static const wrongProductImageCaps = 'wrong_product_image_caps';
  static const uploadPhysicalImages = 'upload_physical_images';
  static const suggestedPrice = 'suggested_price';
  static const describeDiscrepancy = 'describe_discrepancy';
  static const uploadImagesCaps = 'upload_images_caps';
  static const imageCount = 'image_count';
  static const updateReport = 'update_report';
  static const seeFullProduct = 'see_full_product';
  static const enterUpcLabel = 'enter_upc_label';
  static const thrownLabel = 'thrown_label';
  static const addUpcManually = 'add_upc_manually';
  static const addUpcManuallyBody = 'add_upc_manually_body';
  static const enterUpcNumber = 'enter_upc_number';
  static const scanAndAddProduct = 'scan_and_add_product';
  static const useCameraToScan = 'use_camera_to_scan';
  static const upcPrefix = 'upc_prefix';
  static const qtyPrefix = 'qty_prefix';

  // ── Products: edit ──
  static const secGeneral = 'sec_general';
  static const secAuction = 'sec_auction';
  static const secWarehouse = 'sec_warehouse';
  static const secShipping = 'sec_shipping';
  static const secAttributes = 'sec_attributes';
  static const fieldOriginalPrice = 'field_original_price';
  static const fieldStartingPrice = 'field_starting_price';
  static const fieldBottomPrice = 'field_bottom_price';
  static const fieldStockCount = 'field_stock_count';
  static const fieldShippingPrice = 'field_shipping_price';
  static const fieldWeight = 'field_weight';
  static const mustBeNumber = 'must_be_number';
  static const productNameEmpty = 'product_name_empty';
  static const keepOnePhoto = 'keep_one_photo';
  static const nothingChangedYet = 'nothing_changed_yet';
  static const checkTheForm = 'check_the_form';
  static const savedTitle = 'saved_title';
  static const productUpdated = 'product_updated';
  static const couldNotSave = 'could_not_save';
  static const galleryFull = 'gallery_full';
  static const upToPhotos = 'up_to_photos';
  static const useJpgPngWebp = 'use_jpg_png_webp';
  static const somePhotosFailed = 'some_photos_failed';
  static const photosNotUploaded = 'photos_not_uploaded';
  static const discardChangesTitle = 'discard_changes_title';
  static const discardChangesBody = 'discard_changes_body';
  static const keepEditing = 'keep_editing';
  static const discardAction = 'discard_action';
  static const editProduct = 'edit_product';
  static const editLoggedNote = 'edit_logged_note';
  static const editPartialLoadNote = 'edit_partial_load_note';
  static const fieldNameRequired = 'field_name_required';
  static const fieldBrand = 'field_brand';
  static const fieldGender = 'field_gender';
  static const selectAction = 'select_action';
  static const fieldTaxonomy = 'field_taxonomy';
  static const fieldTaxonomyHelp = 'field_taxonomy_help';
  static const fieldShortDescription = 'field_short_description';
  static const fieldDescription = 'field_description';
  static const fieldImages = 'field_images';
  static const savingReplacesGallery = 'saving_replaces_gallery';
  static const bottomPriceHelp = 'bottom_price_help';
  static const usePlatformShipping = 'use_platform_shipping';
  static const shippingPriceNok = 'shipping_price_nok';
  static const weightHelp = 'weight_help';
  static const fieldPrimaryColour = 'field_primary_colour';
  static const fieldColoursAvailable = 'field_colours_available';
  static const noColoursSelected = 'no_colours_selected';
  static const chooseAction = 'choose_action';
  static const fieldTags = 'field_tags';
  static const addTagHint = 'add_tag_hint';
  static const fieldMaterial = 'field_material';
  static const fieldSizing = 'field_sizing';
  static const fieldSize = 'field_size';
  static const fieldSizeType = 'field_size_type';
  static const fieldUsSize = 'field_us_size';
  static const fieldEuSize = 'field_eu_size';
  static const fieldSizesAvailable = 'field_sizes_available';
  static const sizesHint = 'sizes_hint';
  static const fieldDetails = 'field_details';
  static const fieldFeatures = 'field_features';
  static const fieldMaterialsCare = 'field_materials_care';
  static const noChangesYet = 'no_changes_yet';
  static const fieldChanged = 'field_changed';
  static const fieldsChanged = 'fields_changed';
  static const saveChanges = 'save_changes';
  static const saveChangeCount = 'save_change_count';
  static const saveChangesCount = 'save_changes_count';
  static const addAction = 'add_action';
  static const selectedCount = 'selected_count';
  static const searchColours = 'search_colours';
  static const noMatchingColours = 'no_matching_colours';
  static const doneAction = 'done_action';
  static const reasonRequired = 'reason_required';
  static const describeChange = 'describe_change';
  static const reasonForChange = 'reason_for_change';
  static const reasonLoggedNote = 'reason_logged_note';
  static const whyChange = 'why_change';
  static const whyChangeHint = 'why_change_hint';

  // ── Products: detail ──
  static const copiedSuffix = 'copied_suffix';
  static const linkLabel = 'link_label';
  static const productDetails = 'product_details';
  static const mainInformation = 'main_information';
  static const productId = 'product_id';
  static const sexLabel = 'sex_label';
  static const mainCategory = 'main_category';
  static const subcategory = 'subcategory';
  static const tagsKeywords = 'tags_keywords';
  static const pricingAndAuction = 'pricing_and_auction';
  static const catalogPrice = 'catalog_price';
  static const buyNowPrice = 'buy_now_price';
  static const startingPriceAuction = 'starting_price_auction';
  static const bidStep = 'bid_step';
  static const warehouseAndLogistics = 'warehouse_and_logistics';
  static const inStock = 'in_stock';
  static const referenceSku = 'reference_sku';
  static const barcodeUpc = 'barcode_upc';
  static const searchBarcode = 'search_barcode';
  static const mainColor = 'main_color';
  static const availableSizes = 'available_sizes';
  static const colorSelection = 'color_selection';
  static const vendorStyle = 'vendor_style';
  static const extendedDescription = 'extended_description';
  static const briefSummary = 'brief_summary';
  static const fullDescription = 'full_description';
  static const materialsAndCare = 'materials_and_care';
  static const sellerNote = 'seller_note';
  static const shippingAndReturns = 'shipping_and_returns';
  static const sizeChart = 'size_chart';
  static const systemData = 'system_data';
  static const importFlag = 'import_flag';
  static const distributedTo = 'distributed_to';
  static const createdInCatalog = 'created_in_catalog';
  static const lastSynced = 'last_synced';
  static const sellerCount = 'seller_count';
  static const sellersCount = 'sellers_count';
  static const notStated = 'not_stated';
  static const pricePointCaps = 'price_point_caps';
  static const shippingPerOrder = 'shipping_per_order';
  static const freeShippingAt = 'free_shipping_at';
  static const shippingSettings = 'shipping_settings';
  static const useStandardShipping = 'use_standard_shipping';
  static const customShipping = 'custom_shipping';
  static const allowedAmountsCaps = 'allowed_amounts_caps';
  static const maximumPerProduct = 'maximum_per_product';
  static const updateShippingOptions = 'update_shipping_options';
  static const referralLink = 'referral_link';
  static const openAction = 'open_action';
  static const copyAction = 'copy_action';
  static const couldNotLoadDetails = 'could_not_load_details';
  static const retryAction = 'retry_action';
  static const editProductAction = 'edit_product_action';
  static const hiddenLabel = 'hidden_label';
  static const visibleLabel = 'visible_label';
  static const noProductsYet = 'no_products_yet';
  static const noProductsMatch = 'no_products_match';
  static const clearFilters = 'clear_filters';
  static const scrollForMore = 'scroll_for_more';
  static const searchProducts = 'search_products';
  static const filterByStatus = 'filter_by_status';
  static const viewAction = 'view_action';
  static const filterAll = 'filter_all';
  static const filterReserved = 'filter_reserved';

  // ── Dates ──
  static const monthJanuary = 'month_january';
  static const monthFebruary = 'month_february';
  static const monthMarch = 'month_march';
  static const monthApril = 'month_april';
  static const monthMay = 'month_may';
  static const monthJune = 'month_june';
  static const monthJuly = 'month_july';
  static const monthAugust = 'month_august';
  static const monthSeptember = 'month_september';
  static const monthOctober = 'month_october';
  static const monthNovember = 'month_november';
  static const monthDecember = 'month_december';
  static const dateTimeFormat = 'date_time_format';
  static const dateClock24 = 'date_clock_24';
  static const productCountOne = 'product_count_one';
  static const productCountMany = 'product_count_many';

  // ── Become a seller ──
  static const bsFileOpenFailed = 'bs_file_open_failed';
  static const bsPickDocType = 'bs_pick_doc_type';
  static const bsFileReadFailed = 'bs_file_read_failed';
  static const bsFileTooLarge = 'bs_file_too_large';
  static const bsApplicationSubmitted = 'bs_application_submitted';
  static const bsSelectDob = 'bs_select_dob';
  static const bsSellerApplication = 'bs_seller_application';
  static const bsCouldNotLoad = 'bs_could_not_load';
  static const bsUnderReview = 'bs_under_review';
  static const bsUnderReviewBody = 'bs_under_review_body';
  static const bsApproved = 'bs_approved';
  static const bsApprovedBody = 'bs_approved_body';
  static const bsNotApproved = 'bs_not_approved';
  static const bsNotApprovedBody = 'bs_not_approved_body';
  static const bsNoApplication = 'bs_no_application';
  static const bsNoApplicationBody = 'bs_no_application_body';
  static const bsGoToLogin = 'bs_go_to_login';
  static const bsApplicationReceived = 'bs_application_received';
  static const bsPersonalInfo = 'bs_personal_info';
  static const bsFullNameCaps = 'bs_full_name_caps';
  static const bsFirstLastName = 'bs_first_last_name';
  static const bsDobCaps = 'bs_dob_caps';
  static const bsPhoneCaps = 'bs_phone_caps';
  static const bsSellerAddress = 'bs_seller_address';
  static const bsSellerAddressBody = 'bs_seller_address_body';
  static const bsStreetCaps = 'bs_street_caps';
  static const bsStreetHint = 'bs_street_hint';
  static const bsPostalCaps = 'bs_postal_caps';
  static const bsPostalHint = 'bs_postal_hint';
  static const bsExperience = 'bs_experience';
  static const bsComfortQuestion = 'bs_comfort_question';
  static const bsHoursQuestion = 'bs_hours_question';
  static const bsHoursNote = 'bs_hours_note';
  static const bsTypesOfExperience = 'bs_types_of_experience';
  static const bsSelectAllApply = 'bs_select_all_apply';
  static const bsTellUsMoreCaps = 'bs_tell_us_more_caps';
  static const bsDescribeExperience = 'bs_describe_experience';
  static const bsDocumentation = 'bs_documentation';
  static const bsSubmitApplication = 'bs_submit_application';
  static const bsRetrievedFromAccount = 'bs_retrieved_from_account';
  static const bsUploadCv = 'bs_upload_cv';
  static const bsCvFormats = 'bs_cv_formats';
  static const bsReplace = 'bs_replace';
  static const bsConfirmInfo = 'bs_confirm_info';
  static const bsNoReasonGiven = 'bs_no_reason_given';
  static const bsReasonCaps = 'bs_reason_caps';
  static const bsApplyAgainInDays = 'bs_apply_again_in_days';
  static const bsCannotApplyYet = 'bs_cannot_apply_yet';
  static const bsCompleteProfileFirst = 'bs_complete_profile_first';
  static const bsCompleteProfileBody = 'bs_complete_profile_body';

  // ── Application form options (sent as the enum `api` value, shown as this) ──
  static const bsComfortVery = 'bs_comfort_very';
  static const bsComfortComfortable = 'bs_comfort_comfortable';
  static const bsComfortSomewhat = 'bs_comfort_somewhat';
  static const bsComfortWilling = 'bs_comfort_willing';
  static const bsHours1To3 = 'bs_hours_1_3';
  static const bsHours3To6 = 'bs_hours_3_6';
  static const bsHours6To10 = 'bs_hours_6_10';
  static const bsHours10Plus = 'bs_hours_10_plus';
  static const bsExpLiveSales = 'bs_exp_live_sales';
  static const bsExpOnlineRetail = 'bs_exp_online_retail';
  static const bsExpSalesCertificate = 'bs_exp_sales_certificate';
  static const bsExpSaleInStore = 'bs_exp_sale_in_store';
  static const bsExpOther = 'bs_exp_other';

  // ── Application validation + API failures ──
  static const bsInvalidPostal = 'bs_invalid_postal';
  static const bsInvalidEmail = 'bs_invalid_email';
  static const bsNameRequired = 'bs_name_required';
  static const bsMinimumAge = 'bs_minimum_age';
  static const bsExperienceOtherRequired = 'bs_experience_other_required';
  static const bsExperienceOtherTooLong = 'bs_experience_other_too_long';
  static const bsSessionExpired = 'bs_session_expired';
  static const bsNetworkError = 'bs_network_error';
  static const bsAccountReadFailed = 'bs_account_read_failed';
  static const bsStatusLoadFailed = 'bs_status_load_failed';
  static const bsCvUploadFailed = 'bs_cv_upload_failed';
  static const bsSubmitFailed = 'bs_submit_failed';
  static const bsAlreadyApplied = 'bs_already_applied';
  static const bsTooManyRequests = 'bs_too_many_requests';

  // ── Address labels ──
  static const bsCityCaps = 'bs_city_caps';
  static const bsCountryCaps = 'bs_country_caps';
  static const countryNorway = 'country_norway';

  // ── Caps labels ──
  static const followersCaps = 'followers_caps';
  static const emailCaps = 'email_caps';
  static const passwordCaps = 'password_caps';
  static const inventoryCaps = 'inventory_caps';
  static const logisticsCaps = 'logistics_caps';

  // ── Streams ──
  static const statusDraft = 'status_draft';
  static const statusScheduled = 'status_scheduled';
  static const statusLive = 'status_live';
  static const statusEnded = 'status_ended';
  static const statusCancelled = 'status_cancelled';
  static const adminApproved = 'admin_approved';
  static const awaitingAdmin = 'awaiting_admin';
  static const adminRejected = 'admin_rejected';
  static const myStreamsTitle = 'my_streams_title';
  static const myStreamsSub = 'my_streams_sub';
  static const loadMore = 'load_more';
  static const streamAlreadyEnded = 'stream_already_ended';
  static const streamNoLongerLive = 'stream_no_longer_live';
  static const enterRoom = 'enter_room';
  static const requestsOpen = 'requests_open';
  static const noStreamsYetTab = 'no_streams_yet_tab';
  static const tapNewStream = 'tap_new_stream';
  static const nothingHereRightNow = 'nothing_here_right_now';
  static const monthJanShort = 'month_jan_short';
  static const monthFebShort = 'month_feb_short';
  static const monthMarShort = 'month_mar_short';
  static const monthAprShort = 'month_apr_short';
  static const monthMayShort = 'month_may_short';
  static const monthJunShort = 'month_jun_short';
  static const monthJulShort = 'month_jul_short';
  static const monthAugShort = 'month_aug_short';
  static const monthSepShort = 'month_sep_short';
  static const monthOctShort = 'month_oct_short';
  static const monthNovShort = 'month_nov_short';
  static const monthDecShort = 'month_dec_short';

  // ── Create stream ──
  static const csOthers = 'cs_others';
  static const csStreamThumbnail = 'cs_stream_thumbnail';
  static const csUploadFailed = 'cs_upload_failed';
  static const csThumbUploadFailed = 'cs_thumb_upload_failed';
  static const csEnterTitle = 'cs_enter_title';
  static const csUploadThumb = 'cs_upload_thumb';
  static const csSelectSize = 'cs_select_size';
  static const csChooseStartTime = 'cs_choose_start_time';
  static const csTimeMustBeFuture = 'cs_time_must_be_future';
  static const csMissingInformation = 'cs_missing_information';
  static const csStreamUpdated = 'cs_stream_updated';
  static const csStreamCreated = 'cs_stream_created';
  static const csChangesSaved = 'cs_changes_saved';
  static const csStreamCreatedBody = 'cs_stream_created_body';
  static const csCouldNotUpdate = 'cs_could_not_update';
  static const csCouldNotCreate = 'cs_could_not_create';
  static const csEditStream = 'cs_edit_stream';
  static const csShipmentInfo = 'cs_shipment_info';
  static const csTitle = 'cs_title';
  static const csTitleHint = 'cs_title_hint';
  static const csDescriptionHint = 'cs_description_hint';
  static const csThumbnail = 'cs_thumbnail';
  static const csThumbnailHelp = 'cs_thumbnail_help';
  static const csSizes = 'cs_sizes';
  static const csChange = 'cs_change';
  static const csTimeOfSending = 'cs_time_of_sending';
  static const csStartNow = 'cs_start_now';
  static const csGoLiveRightAway = 'cs_go_live_right_away';
  static const csPlan = 'cs_plan';
  static const csChooseLaterTime = 'cs_choose_later_time';
  static const csScheduledStartTime = 'cs_scheduled_start_time';
  static const csSelectDateTime = 'cs_select_date_time';
  static const csEstimatedDuration = 'cs_estimated_duration';
  static const csMinUnit = 'cs_min_unit';
  static const csHourUnit = 'cs_hour_unit';
  static const csUpdateStream = 'cs_update_stream';
  static const csCreateAndGoLive = 'cs_create_and_go_live';
  static const csCreateStream = 'cs_create_stream';
  static const csTapToUpload = 'cs_tap_to_upload';
  static const csPortraitHint = 'cs_portrait_hint';
  static const csYou = 'cs_you';

  // ── Stream analytics ──
  static const saStream = 'sa_stream';
  static const saStreamAnalysis = 'sa_stream_analysis';
  static const saCouldNotLoad = 'sa_could_not_load';
  static const saStatusCaps = 'sa_status_caps';
  static const saMaxViewers = 'sa_max_viewers';
  static const saStoredValue = 'sa_stored_value';
  static const saAvgViewers = 'sa_avg_viewers';
  static const saStreamDuration = 'sa_stream_duration';
  static const saAuctionTime = 'sa_auction_time';
  static const saViewersNow = 'sa_viewers_now';
  static const saStarted = 'sa_started';
  static const saCompleted = 'sa_completed';
  static const saAuctioned = 'sa_auctioned';
  static const saNotSold = 'sa_not_sold';
  static const saSalesSummary = 'sa_sales_summary';
  static const saTotalTurnover = 'sa_total_turnover';
  static const saPaid = 'sa_paid';
  static const saUnpaid = 'sa_unpaid';
  static const saNumberOfBuyers = 'sa_number_of_buyers';
  static const saAuctionsInStream = 'sa_auctions_in_stream';
  static const saNoAuctionsYet = 'sa_no_auctions_yet';
  static const saBuyers = 'sa_buyers';
  static const saNoOrders = 'sa_no_orders';
  static const saRetrieved = 'sa_retrieved';
  static const saGeneratedByServer = 'sa_generated_by_server';
  static const saHourShort = 'sa_hour_short';
  static const saMinuteShort = 'sa_minute_short';
  static const saSecondShort = 'sa_second_short';
  static const saBidsCount = 'sa_bids_count';
  static const saProduct = 'sa_product';
  static const saStartPrice = 'sa_start_price';
  static const saSoldCaps = 'sa_sold_caps';
  static const saNotSoldCaps = 'sa_not_sold_caps';
  static const saBuyer = 'sa_buyer';
  static const saPending = 'sa_pending';
  static const saUnpaidCaps = 'sa_unpaid_caps';

  // ── Duration words ──
  static const durHourOne = 'dur_hour_one';
  static const durHourMany = 'dur_hour_many';
  static const durMinuteOne = 'dur_minute_one';
  static const durMinuteMany = 'dur_minute_many';
  static const durSecondOne = 'dur_second_one';
  static const durSecondMany = 'dur_second_many';
  static const dateStampFormat = 'date_stamp_format';

  // ── Order statuses ──
  static const osPaid = 'os_paid';
  static const osAwaitingPayment = 'os_awaiting_payment';
  static const osFailed = 'os_failed';
  static const osRefunded = 'os_refunded';
  static const osNotCreated = 'os_not_created';
  static const osCreated = 'os_created';
  static const osInTransit = 'os_in_transit';
  static const osDelivered = 'os_delivered';
  static const osCancelled = 'os_cancelled';
  static const osReadyForPickup = 'os_ready_for_pickup';
  static const osPickedUp = 'os_picked_up';
  static const osLocalPickup = 'os_local_pickup';

  // ── Orders ──
  static const ordAllOrdersSub = 'ord_all_orders_sub';
  static const ordSearchHint = 'ord_search_hint';
  static const ordFilterBy = 'ord_filter_by';
  static const ordAllPaymentStatuses = 'ord_all_payment_statuses';
  static const ordAllShippingStatuses = 'ord_all_shipping_statuses';
  static const ordShowDetails = 'ord_show_details';
  static const ordNoMatchingOrders = 'ord_no_matching_orders';
  static const ordNoOrdersYet = 'ord_no_orders_yet';
  static const ordNothingMatches = 'ord_nothing_matches';
  static const ordWillShowHere = 'ord_will_show_here';
  static const ordCouldNotLoad = 'ord_could_not_load';
  static const ordOrderNumberHash = 'ord_order_number_hash';
  static const ordOrderSummary = 'ord_order_summary';
  static const ordOrderNumberCaps = 'ord_order_number_caps';
  static const ordCreatedDateCaps = 'ord_created_date_caps';
  static const ordProductCaps = 'ord_product_caps';
  static const ordTotalAmountCaps = 'ord_total_amount_caps';
  static const ordProductsColon = 'ord_products_colon';
  static const ordShippingColon = 'ord_shipping_colon';
  static const ordRefundedColon = 'ord_refunded_colon';
  static const ordBuyerInformation = 'ord_buyer_information';
  static const ordContactDetailsCaps = 'ord_contact_details_caps';
  static const ordFullName = 'ord_full_name';
  static const ordEmailAddress = 'ord_email_address';
  static const ordCustomerId = 'ord_customer_id';
  static const ordPhoneNumber = 'ord_phone_number';
  static const ordShippingAddressCaps = 'ord_shipping_address_caps';
  static const ordSellerDetails = 'ord_seller_details';
  static const ordDisplayName = 'ord_display_name';
  static const ordPaymentTimeline = 'ord_payment_timeline';
  static const ordNoPaymentAttempts = 'ord_no_payment_attempts';
  static const ordFinalPaymentAt = 'ord_final_payment_at';
  static const ordDeliveredAt = 'ord_delivered_at';
  static const ordReadyPickupNote = 'ord_ready_pickup_note';
  static const ordInvalidLink = 'ord_invalid_link';
  static const ordInvalidLinkBody = 'ord_invalid_link_body';
  static const ordCouldNotOpen = 'ord_could_not_open';
  static const ordNoAppForLink = 'ord_no_app_for_link';
  static const ordTrackShipment = 'ord_track_shipment';
  static const ordCouldNotRefresh = 'ord_could_not_refresh';
  static const ordCouldNotLoadOrder = 'ord_could_not_load_order';
  static const ordCheckConnection = 'ord_check_connection';
  static const ordDayFormat = 'ord_day_format';

  // ── Notifications ──
  static const ntNothingToOpen = 'nt_nothing_to_open';
  static const ntAllMarkedRead = 'nt_all_marked_read';
  static const ntAllArchived = 'nt_all_archived';
  static const ntArchiveAll = 'nt_archive_all';
  static const ntArchiveAllBody = 'nt_archive_all_body';
  static const ntArchive = 'nt_archive';
  static const ntNotifications = 'nt_notifications';
  static const ntMarkAllRead = 'nt_mark_all_read';
  static const ntUnread = 'nt_unread';
  static const ntArchived = 'nt_archived';
  static const ntTopicAuction = 'nt_topic_auction';
  static const ntTopicOrder = 'nt_topic_order';
  static const ntTopicOffer = 'nt_topic_offer';
  static const ntTopicPayment = 'nt_topic_payment';
  static const ntTopicShipping = 'nt_topic_shipping';
  static const ntTopicStream = 'nt_topic_stream';
  static const ntTopicSocial = 'nt_topic_social';
  static const ntTopicSeller = 'nt_topic_seller';
  static const ntTopicBuyer = 'nt_topic_buyer';
  static const ntTopicAdmin = 'nt_topic_admin';
  static const ntTopicSecurity = 'nt_topic_security';
  static const ntTopicMarketing = 'nt_topic_marketing';
  static const ntMarkAsUnread = 'nt_mark_as_unread';
  static const ntMarkAsRead = 'nt_mark_as_read';
  static const ntNothingInTopic = 'nt_nothing_in_topic';
  static const ntNothingInTopicBody = 'nt_nothing_in_topic_body';
  static const ntAllCaughtUp = 'nt_all_caught_up';
  static const ntAllCaughtUpBody = 'nt_all_caught_up_body';
  static const ntNothingArchived = 'nt_nothing_archived';
  static const ntNothingArchivedBody = 'nt_nothing_archived_body';
  static const ntNoNotificationsYet = 'nt_no_notifications_yet';
  static const ntNoNotificationsBody = 'nt_no_notifications_body';
  static const ntUnavailable = 'nt_unavailable';
  static const ntUnavailableBody = 'nt_unavailable_body';

  // ── Edit profile ──
  static const epRequired = 'ep_required';
  static const epDisplayNameEmpty = 'ep_display_name_empty';
  static const epBusinessNameEmpty = 'ep_business_name_empty';
  static const epProfileUpdated = 'ep_profile_updated';
  static const epCouldNotUpdate = 'ep_could_not_update';
  static const epEditProfile = 'ep_edit_profile';
  static const epBasicInformation = 'ep_basic_information';
  static const epDisplayName = 'ep_display_name';
  static const epBusinessName = 'ep_business_name';
  static const epPublicSlug = 'ep_public_slug';
  static const epPublicSections = 'ep_public_sections';
  static const epPublicSectionsBody = 'ep_public_sections_body';
  static const epHeader = 'ep_header';
  static const epStats = 'ep_stats';
  static const epBusinessInfo = 'ep_business_info';
  static const epAccountInfo = 'ep_account_info';
  static const epSocialLinksTitle = 'ep_social_links_title';
  static const epSocialLinksBody = 'ep_social_links_body';
  static const epWebsiteHint = 'ep_website_hint';
  static const epInstagramHint = 'ep_instagram_hint';
  static const epAboutStoreHint = 'ep_about_store_hint';

  // ── Relative time ──
  static const timeNow = 'time_now';
  static const timeMinutesShort = 'time_minutes_short';
  static const timeHoursShort = 'time_hours_short';
  static const timeDaysShort = 'time_days_short';

  // ── Stock ──
  static const stRecentActivity = 'st_recent_activity';
  static const stPlacementCreated = 'st_placement_created';
  static const stProductAddedToBin = 'st_product_added_to_bin';
  static const stTwoHoursAgo = 'st_two_hours_ago';
  static const stLocationUpdated = 'st_location_updated';
  static const stBinRenamed = 'st_bin_renamed';
  static const stYesterday = 'st_yesterday';
  static const stProductAddedToSku = 'st_product_added_to_sku';
  static const stSomethingWentWrong = 'st_something_went_wrong';
  static const stCouldNotUploadNamed = 'st_could_not_upload_named';
  static const stAddImage = 'st_add_image';
  static const stTakeAPhoto = 'st_take_a_photo';
  static const stChooseFromGallery = 'st_choose_from_gallery';
  static const stEnterQuantityOne = 'st_enter_quantity_one';
  static const stQuantity = 'st_quantity';
  static const stEnterQuantity = 'st_enter_quantity';
  static const stUploadingImages = 'st_uploading_images';
  static const stAddProduct = 'st_add_product';
  static const stAssignFlowHint = 'st_assign_flow_hint';
  static const stSelectSku = 'st_select_sku';
  static const stSearchSkuHint = 'st_search_sku_hint';
  static const stStartTypingSku = 'st_start_typing_sku';
  static const stNoSkusMatch = 'st_no_skus_match';
  static const stManageSkus = 'st_manage_skus';
  static const stSearchOpenSkus = 'st_search_open_skus';
  static const stAssignToSku = 'st_assign_to_sku';
  static const stScanProductsIn = 'st_scan_products_in';
  static const stSearch = 'st_search';
  static const stByUpcOrTag = 'st_by_upc_or_tag';
  static const stNewSku = 'st_new_sku';
  static const stCreateABin = 'st_create_a_bin';
  static const stFindASku = 'st_find_a_sku';
  static const stFindASkuBody = 'st_find_a_sku_body';
  static const stSearchSkuShort = 'st_search_sku_short';
  static const stNoMatchingTags = 'st_no_matching_tags';
  static const stEnterOrScanUpc = 'st_enter_or_scan_upc';
  static const stTypeUpcHint = 'st_type_upc_hint';
  static const stSearchTagsHint = 'st_search_tags_hint';
  static const stSearchTagBody = 'st_search_tag_body';
  static const stFindSkuByCode = 'st_find_sku_by_code';
  static const stTag = 'st_tag';
  static const stScan = 'st_scan';
  static const stEnterUpcOrTag = 'st_enter_upc_or_tag';
  static const stNoMatchesFound = 'st_no_matches_found';
  static const stSearchSkuToSee = 'st_search_sku_to_see';
  static const stSearchTagToList = 'st_search_tag_to_list';
  static const stQuickViewLower = 'st_quick_view_lower';
  static const stAssigned = 'st_assigned';
  static const stCannotRemoveNow = 'st_cannot_remove_now';
  static const stRemoveFromSku = 'st_remove_from_sku';
  static const stProductRemoved = 'st_product_removed';
  static const stCannotMoveNow = 'st_cannot_move_now';
  static const stNoProductsAssigned = 'st_no_products_assigned';
  static const stThisProduct = 'st_this_product';
  static const stDeleteProductTitle = 'st_delete_product_title';
  static const stDeleteConfirm = 'st_delete_confirm';
  static const stDeletedTitle = 'st_deleted_title';
  static const stPendingRemoved = 'st_pending_removed';
  static const stNoPendingProducts = 'st_no_pending_products';
  static const stQtyShort = 'st_qty_short';
  static const stPrimaryCaps = 'st_primary_caps';
  static const stInvalidQuantity = 'st_invalid_quantity';
  static const stEnterQtyOneOrMore = 'st_enter_qty_one_or_more';
  static const stAddedToQuantity = 'st_added_to_quantity';
  static const stCurrentQuantity = 'st_current_quantity';
  static const stAddQuantityCaps = 'st_add_quantity_caps';
  static const stPrimaryLocation = 'st_primary_location';
  static const stSaveAction = 'st_save_action';
  static const stPickASku = 'st_pick_a_sku';
  static const stPickTargetSku = 'st_pick_target_sku';
  static const stMovedTitle = 'st_moved_title';
  static const stProductMovedTo = 'st_product_moved_to';
  static const stCouldNotMove = 'st_could_not_move';
  static const stMoveNamed = 'st_move_named';
  static const stSearchSkuToMove = 'st_search_sku_to_move';
  static const stMove = 'st_move';
  static const stMoveTo = 'st_move_to';
  static const stMissingName = 'st_missing_name';
  static const stEnterAProductName = 'st_enter_a_product_name';
  static const stEnterQtyZeroOrMore = 'st_enter_qty_zero_or_more';
  static const stPendingUpdated = 'st_pending_updated';
  static const stEditPendingProduct = 'st_edit_pending_product';
  static const stNameCaps = 'st_name_caps';
  static const stQuantityCaps = 'st_quantity_caps';
  static const stImagesCaps = 'st_images_caps';
  static const stOverview = 'st_overview';
  static const stSkus = 'st_skus';
  static const stTotalCaps = 'st_total_caps';
  static const stAssignedCaps = 'st_assigned_caps';
  static const stTotalSkusCaps = 'st_total_skus_caps';
  static const stActiveSkusCaps = 'st_active_skus_caps';
  static const stProductsAssignedCaps = 'st_products_assigned_caps';
  static const stSumOfAssignments = 'st_sum_of_assignments';
  static const stAssignProductCaps = 'st_assign_product_caps';
  static const stAssignProductBody = 'st_assign_product_body';
  static const stProductsInSkuCaps = 'st_products_in_sku_caps';
  static const stSkuCodeCaps = 'st_sku_code_caps';
  static const stProductCountCaps = 'st_product_count_caps';
  static const stProductCountCapsMany = 'st_product_count_caps_many';
  static const stPrimaryCountCaps = 'st_primary_count_caps';
  static const stSkuTagsCaps = 'st_sku_tags_caps';
  static const stNoTags = 'st_no_tags';
  static const stSearchSkuOrCreate = 'st_search_sku_or_create';
  static const stWarehouse = 'st_warehouse';
  static const stWarehouseSub = 'st_warehouse_sub';
  static const stMissingInfo = 'st_missing_info';
  static const stTypeTagName = 'st_type_tag_name';
  static const stEnterValidTag = 'st_enter_valid_tag';
  static const stCouldNotCreateTag = 'st_could_not_create_tag';
  static const stSkuCodeRequired = 'st_sku_code_required';
  static const stCreatedTitle = 'st_created_title';
  static const stSkuUpdated = 'st_sku_updated';
  static const stSkuCreated = 'st_sku_created';
  static const stEditSku = 'st_edit_sku';
  static const stZoneCaps = 'st_zone_caps';
  static const stRackCaps = 'st_rack_caps';
  static const stShelfCaps = 'st_shelf_caps';
  static const stSortOrderCaps = 'st_sort_order_caps';
  static const stSkuCodeRequiredCaps = 'st_sku_code_required_caps';
  static const stAutoFilled = 'st_auto_filled';
  static const stOptionalDisplayName = 'st_optional_display_name';
  static const stNotesCaps = 'st_notes_caps';
  static const stCreateSku = 'st_create_sku';
  static const stSearchTagsShort = 'st_search_tags_short';
  static const stNewTag = 'st_new_tag';
  static const stNewSkuTagCaps = 'st_new_sku_tag_caps';
  static const stLabelCaps = 'st_label_caps';
  static const stTagExample = 'st_tag_example';
  static const stAddSkuTag = 'st_add_sku_tag';
  static const stLoadingDetails = 'st_loading_details';
  static const stQuantityColon = 'st_quantity_colon';
  static const stUpcColon = 'st_upc_colon';
  static const stSuggestedRetail = 'st_suggested_retail';
  static const stInStockCaps = 'st_in_stock_caps';
  static const stPcs = 'st_pcs';
  static const stSubmitReport = 'st_submit_report';

  // ── Stock badges ──
  static const stProductsAssignedBadge = 'st_products_assigned_badge';
  static const stProductAssignedBadge = 'st_product_assigned_badge';

  // ── Measurements ──
  static const msCouldNotLoad = 'ms_could_not_load';
  static const msOnlyImageTypes = 'ms_only_image_types';
  static const msTooLarge = 'ms_too_large';
  static const msMaxFiveMb = 'ms_max_five_mb';
  static const msEnterValueFor = 'ms_enter_value_for';
  static const msEnterValidCm = 'ms_enter_valid_cm';
  static const msMeasurementsSaved = 'ms_measurements_saved';
  static const msSkuScope = 'ms_sku_scope';
  static const msOptionalMeasurements = 'ms_optional_measurements';
  static const msMeasurements = 'ms_measurements';
  static const msAddedCount = 'ms_added_count';
  static const msNoMeasurements = 'ms_no_measurements';
  static const msPickTargetType = 'ms_pick_target_type';
  static const msSelectTargetType = 'ms_select_target_type';
  static const msAllTargetTypes = 'ms_all_target_types';
  static const msMeasurementPhotos = 'ms_measurement_photos';
  static const msPhotoHint = 'ms_photo_hint';
  static const msLimit = 'ms_limit';
  static const msAddPhoto = 'ms_add_photo';
  static const msSaveMeasurements = 'ms_save_measurements';

  // ── Scanner ──
  static const scScanBarcode = 'sc_scan_barcode';
  static const scHoldInFrame = 'sc_hold_in_frame';
  static const scBarcodeFound = 'sc_barcode_found';
  static const scCodeCaps = 'sc_code_caps';
  static const scEnterCode = 'sc_enter_code';
  static const scScanAgain = 'sc_scan_again';
  static const scDone = 'sc_done';
  static const scQrCode = 'sc_qr_code';
  static const scBarcode = 'sc_barcode';
  static const siDeleteItemTitle = 'si_delete_item_title';
  static const siDeleteItemBody = 'si_delete_item_body';
  static const siScanInventory = 'si_scan_inventory';
  static const siItemCount = 'si_item_count';
  static const siItemCountMany = 'si_item_count_many';
  static const siNoItemsScanned = 'si_no_items_scanned';
  static const siTapScanBarcode = 'si_tap_scan_barcode';

  // ── Scan inventory units ──
  static const siUnitCount = 'si_unit_count';
  static const siUnitCountMany = 'si_unit_count_many';

  // ── Auction room ──
  static const arLeaveRoomTitle = 'ar_leave_room_title';
  static const arLeaveRoomBody = 'ar_leave_room_body';
  static const arLeave = 'ar_leave';
  static const arAuctionRoom = 'ar_auction_room';
  static const arLiveCaps = 'ar_live_caps';
  static const arTabLive = 'ar_tab_live';
  static const arTabQueue = 'ar_tab_queue';
  static const arTabChat = 'ar_tab_chat';
  static const arOpeningRoom = 'ar_opening_room';
  static const arPermissionTitle = 'ar_permission_title';
  static const arPermissionSettings = 'ar_permission_settings';
  static const arPermissionPrompt = 'ar_permission_prompt';
  static const arOpenSettings = 'ar_open_settings';
  static const arAllowAccess = 'ar_allow_access';
  static const arCouldNotOpenRoom = 'ar_could_not_open_room';
  static const arStreamEnded = 'ar_stream_ended';
  static const arStreamFinished = 'ar_stream_finished';
  static const arBackToStreams = 'ar_back_to_streams';

  // ── Live tab ──
  static const ltConnectionLost = 'lt_connection_lost';
  static const ltWaitingForControl = 'lt_waiting_for_control';
  static const ltRequestControl = 'lt_request_control';
  static const ltGoLive = 'lt_go_live';
  static const ltStopLive = 'lt_stop_live';
  static const ltStartingCamera = 'lt_starting_camera';
  static const ltCameraOff = 'lt_camera_off';
  static const ltPreviewOnly = 'lt_preview_only';
  static const ltLiveStopped = 'lt_live_stopped';
  static const ltUnmute = 'lt_unmute';
  static const ltMute = 'lt_mute';
  static const ltFlip = 'lt_flip';
  static const ltNoAuctionRunning = 'lt_no_auction_running';
  static const ltAddProductsFirst = 'lt_add_products_first';
  static const ltStartNextLot = 'lt_start_next_lot';
  static const ltStartAuction = 'lt_start_auction';
  static const ltGoLiveToStart = 'lt_go_live_to_start';
  static const ltCurrentLot = 'lt_current_lot';
  static const ltCurrentPrice = 'lt_current_price';
  static const ltHighestBid = 'lt_highest_bid';
  static const ltBids = 'lt_bids';
  static const ltLeading = 'lt_leading';
  static const ltReducePrice = 'lt_reduce_price';
  static const ltEndLot = 'lt_end_lot';
  static const ltReduceDutchPrice = 'lt_reduce_dutch_price';
  static const ltCurrentColon = 'lt_current_colon';
  static const ltNewPriceKr = 'lt_new_price_kr';
  static const ltReduce = 'lt_reduce';
  static const ltLastLot = 'lt_last_lot';
  static const ltSoldTo = 'lt_sold_to';
  static const ltNoWinner = 'lt_no_winner';
  static const ltTimeLeft = 'lt_time_left';
  static const ltExtend = 'lt_extend';

  // ── Chat tab ──
  static const ctLiveChat = 'ct_live_chat';
  static const ctEnable = 'ct_enable';
  static const ctDisable = 'ct_disable';
  static const ctClear = 'ct_clear';
  static const ctNoMessages = 'ct_no_messages';
  static const ctDeleteMessage = 'ct_delete_message';
  static const ctUnmuteViewer = 'ct_unmute_viewer';

  // ── Moderation: reporting user-generated content (guideline 1.2) ────────
  // Mute/delete only tidy up the seller's own room. These label the path that
  // actually reaches an operator, which App Review requires a UGC app to have.
  static const ctReportMessage      = 'ct_report_message';
  static const reportTitle          = 'report_title';
  static const reportBody           = 'report_body';
  static const reportNoteHint       = 'report_note_hint';
  static const reportSubmit         = 'report_submit';
  static const reportSent           = 'report_sent';
  static const reportFailed         = 'report_failed';
  static const reportReasonSexual   = 'report_reason_sexual';
  static const reportReasonViolence = 'report_reason_violence';
  static const reportReasonHarassment = 'report_reason_harassment';
  static const reportReasonHate     = 'report_reason_hate';
  static const reportReasonSpam     = 'report_reason_spam';
  static const reportReasonIllegal  = 'report_reason_illegal';
  static const reportReasonOther    = 'report_reason_other';
  static const ctMuteViewer = 'ct_mute_viewer';
  static const ctClearChatTitle = 'ct_clear_chat_title';
  static const ctClearChatBody = 'ct_clear_chat_body';
  static const ctYouHost = 'ct_you_host';
  static const ctUserPrefix = 'ct_user_prefix';
  static const ctChatDisabled = 'ct_chat_disabled';
  static const ctMessageHint = 'ct_message_hint';

  // ── Queue tab ──
  static const qtAddProduct = 'qt_add_product';
  static const qtClearQueueTitle = 'qt_clear_queue_title';
  static const qtClearQueueBody = 'qt_clear_queue_body';
  static const qtRemoveFromQueue = 'qt_remove_from_queue';
  static const qtFromKr = 'qt_from_kr';
  static const qtPreBids = 'qt_pre_bids';
  static const qtAddRandomProduct = 'qt_add_random_product';
  static const qtSelectAll = 'qt_select_all';
  static const qtClearAll = 'qt_clear_all';
  static const qtNoProductsAvailable = 'qt_no_products_available';
  static const qtRandomStreamProduct = 'qt_random_stream_product';
  static const qtProductImage = 'qt_product_image';
  static const qtImageTooLarge = 'qt_image_too_large';
  static const qtPickSmallerImage = 'qt_pick_smaller_image';
  static const qtGiveTitle = 'qt_give_title';
  static const qtAddShortDescription = 'qt_add_short_description';
  static const qtStockRange = 'qt_stock_range';
  static const qtPickProductImage = 'qt_pick_product_image';
  static const qtAddedToQueue = 'qt_added_to_queue';
  static const qtLinedUpAsRandom = 'qt_lined_up_as_random';
  static const qtCreateRandomProduct = 'qt_create_random_product';
  static const qtMysteryItem = 'qt_mystery_item';
  static const qtStock = 'qt_stock';
  static const qtImage = 'qt_image';
  static const qtCreate = 'qt_create';
  static const qtChooseFile = 'qt_choose_file';
  static const qtInQueue = 'qt_in_queue';
  static const qtAddCount = 'qt_add_count';
  static const qtQueueEmpty = 'qt_queue_empty';
  static const qtTapAddProduct = 'qt_tap_add_product';

  // ── Orders tab & control dialog ──
  static const otWinningOrders = 'ot_winning_orders';
  static const otOrderNumber = 'ot_order_number';
  static const otLot = 'ot_lot';
  static const otWinner = 'ot_winner';
  static const otNoOrdersYet = 'ot_no_orders_yet';
  static const otOrdersAppearHere = 'ot_orders_appear_here';
  static const cdMainDevice = 'cd_main_device';
  static const cdSecondaryDevice = 'cd_secondary_device';
  static const cdMainDeviceRequest = 'cd_main_device_request';
  static const cdAuctionControlRequest = 'cd_auction_control_request';
  static const cdAcceptMainBody = 'cd_accept_main_body';
  static const cdAcceptControlBody = 'cd_accept_control_body';
  static const cdAnotherDeviceMain = 'cd_another_device_main';
  static const cdAnotherDeviceControl = 'cd_another_device_control';
  static const cdDevice = 'cd_device';
  static const cdRole = 'cd_role';
  static const cdRequested = 'cd_requested';
  static const cdDecline = 'cd_decline';
  static const cdAccept = 'cd_accept';
  static const cdJustNow = 'cd_just_now';
  static const cdMinAgo = 'cd_min_ago';
  static const cdHoursAgo = 'cd_hours_ago';
  static const cdDaysAgo = 'cd_days_ago';

  // ── Camera / lens selector ──
  static const csFront = 'cs_front';
  static const csBack = 'cs_back';
  static const csWide = 'cs_wide';
  static const csUltraWide = 'cs_ultra_wide';
  static const csTelephoto = 'cs_telephoto';
  static const csSwitching = 'cs_switching';
  static const csSwitchFailed = 'cs_switch_failed';
  static const csNoCameras = 'cs_no_cameras';
  static const csDetecting = 'cs_detecting';
  static const csDeviceDefault = 'cs_device_default';

  // ── Room sheets ──
  static const rsDevicesControl = 'rs_devices_control';
  static const rsMediaPush = 'rs_media_push';
  static const rsStreamAnnouncement = 'rs_stream_announcement';
  static const rsNoActiveAnnouncement = 'rs_no_active_announcement';
  static const rsExtendStream = 'rs_extend_stream';
  static const rsEndStream = 'rs_end_stream';
  static const rsEndStreamTitle = 'rs_end_stream_title';
  static const rsEndStreamBody = 'rs_end_stream_body';
  static const rsEnd = 'rs_end';
  static const rsSetupPlatforms = 'rs_setup_platforms';
  static const rsRestreamToOthers = 'rs_restream_to_others';
  static const rsViewOnlyPrimary = 'rs_view_only_primary';
  static const rsEndsAt = 'rs_ends_at';
  static const rsMinsShort = 'rs_mins_short';
  static const rsPlannedLength = 'rs_planned_length';
  static const rsWriteBannerMessage = 'rs_write_banner_message';
  static const rsAnnouncementLiveOnly = 'rs_announcement_live_only';
  static const rsNoActiveAnnouncementDot = 'rs_no_active_announcement_dot';
  static const rsShowingToBuyers = 'rs_showing_to_buyers';
  static const rsEndingInAMinute = 'rs_ending_in_a_minute';
  static const rsEndingInMin = 'rs_ending_in_min';
  static const rsAboutToEndBody = 'rs_about_to_end_body';
  static const rsPlusMin = 'rs_plus_min';
  static const rsNotNow = 'rs_not_now';
  static const rsEndsArrow = 'rs_ends_arrow';
  static const rsPlusMinutes = 'rs_plus_minutes';
  static const rsExtend = 'rs_extend';
  static const rsRequestMainDevice = 'rs_request_main_device';
  static const rsWaitingMainApproval = 'rs_waiting_main_approval';
  static const rsNoMainRequests = 'rs_no_main_requests';
  static const rsWantsMainDevice = 'rs_wants_main_device';
  static const rsAuctionControl = 'rs_auction_control';
  static const rsRequestAuctionControl = 'rs_request_auction_control';
  static const rsWaitingControlApproval = 'rs_waiting_control_approval';
  static const rsNoControlRequests = 'rs_no_control_requests';
  static const rsWantsAuctionControl = 'rs_wants_auction_control';
  static const rsConnectedDevices = 'rs_connected_devices';
  static const rsNoDevicesReported = 'rs_no_devices_reported';
  static const rsDeviceNamed = 'rs_device_named';
  static const rsDeviceNamedRole = 'rs_device_named_role';
  static const rsControlCaps = 'rs_control_caps';
  static const rsStreamOrders = 'rs_stream_orders';
  static const rsNoOrdersYetDot = 'rs_no_orders_yet_dot';
  static const rsOrder = 'rs_order';
  static const rsPreBidsFor = 'rs_pre_bids_for';
  static const rsNoPreBids = 'rs_no_pre_bids';
  static const rsBack = 'rs_back';
  static const rsDeviceWantsMain = 'rs_device_wants_main';
  static const rsDeviceWantsControl = 'rs_device_wants_control';
  static const rsReject = 'rs_reject';
  static const rsApprove = 'rs_approve';
  static const sasStartAuction = 'sas_start_auction';
  static const sasAuctionType = 'sas_auction_type';
  static const sasRegular = 'sas_regular';
  static const sasDutch = 'sas_dutch';
  static const sasDuration = 'sas_duration';
  static const sasStartingPriceOptional = 'sas_starting_price_optional';

  // ── Media push ──
  static const mpMediaPush = 'mp_media_push';
  static const mpMore = 'mp_more';
  static const mpRestartConverters = 'mp_restart_converters';
  static const mpSecondaryDeviceNote = 'mp_secondary_device_note';
  static const mpDismiss = 'mp_dismiss';
  static const mpOnlyPrimaryChange = 'mp_only_primary_change';
  static const mpRemoveDestTitle = 'mp_remove_dest_title';
  static const mpRemoveDestBody = 'mp_remove_dest_body';
  static const mpStopTitle = 'mp_stop_title';
  static const mpStopBody = 'mp_stop_body';
  static const mpStop = 'mp_stop';
  static const mpRestartTitle = 'mp_restart_title';
  static const mpRestartBody = 'mp_restart_body';
  static const mpRestart = 'mp_restart';
  static const mpPushing = 'mp_pushing';
  static const mpIdle = 'mp_idle';
  static const mpStreamIsLive = 'mp_stream_is_live';
  static const mpGoLiveFirst = 'mp_go_live_first';
  static const mpThisDeviceIsPrimary = 'mp_this_device_is_primary';
  static const mpTakeMainControl = 'mp_take_main_control';
  static const mpCameraDetected = 'mp_camera_detected';
  static const mpStartCameraHint = 'mp_start_camera_hint';
  static const mpAtLeastOneDest = 'mp_at_least_one_dest';
  static const mpAddPlatformBelow = 'mp_add_platform_below';
  static const mpDestinations = 'mp_destinations';
  static const mpNoDestinations = 'mp_no_destinations';
  static const mpAddPlatformsBody = 'mp_add_platforms_body';
  static const mpAddDestination = 'mp_add_destination';
  static const mpKeyPrefix = 'mp_key_prefix';
  static const mpAutoStart = 'mp_auto_start';
  static const mpAutoStartBody = 'mp_auto_start_body';
  static const mpStopping = 'mp_stopping';
  static const mpStopMediaPush = 'mp_stop_media_push';
  static const mpStarting = 'mp_starting';
  static const mpStartMediaPush = 'mp_start_media_push';
  static const mpStartWarning = 'mp_start_warning';
  static const mpLiveConverters = 'mp_live_converters';
  static const mpDuplicateConverters = 'mp_duplicate_converters';
  static const mpStreaming = 'mp_streaming';
  static const mpFailed = 'mp_failed';
  static const mpConnecting = 'mp_connecting';
  static const mpNoVideoLayout = 'mp_no_video_layout';
  static const mpPassthrough = 'mp_passthrough';
  static const mpStillConnecting = 'mp_still_connecting';
  static const mpFooterNote = 'mp_footer_note';
  static const mpEditDestination = 'mp_edit_destination';
  static const mpPasteIngest = 'mp_paste_ingest';
  static const mpPlatform = 'mp_platform';
  static const mpRtmpUrl = 'mp_rtmp_url';
  static const mpRtmpHint = 'mp_rtmp_hint';
  static const mpStreamKey = 'mp_stream_key';
  static const mpStreamKeyOptional = 'mp_stream_key_optional';
  static const mpPasteStreamKey = 'mp_paste_stream_key';
  static const mpPlatformNeedsCamera = 'mp_platform_needs_camera';

  // ── Auction interpolated ──
  static const arPlannedAt = 'ar_planned_at';
  static const ltSoldToPrice = 'lt_sold_to_price';
  static const ltBuyerFallback = 'lt_buyer_fallback';
  static const ltLeftEndsAt = 'lt_left_ends_at';
  static const rsUnderAMinute = 'rs_under_a_minute';
  static const rsEndsAtLeft = 'rs_ends_at_left';

  // ── Auction type badges ──
  static const auctionTypeDutchCaps = 'auction_type_dutch_caps';
  static const auctionTypeNormalCaps = 'auction_type_normal_caps';

  // ── Media push extra ──
  static const mpSomeDestFailed = 'mp_some_dest_failed';

  // ── Service errors ──
  static const svcManagedSellersOnly = 'svc_managed_sellers_only';
  static const svcLookupFailed = 'svc_lookup_failed';
  static const svcNetworkError = 'svc_network_error';
  static const svcNoFileKey = 'svc_no_file_key';
  static const svcUnexpectedResponse = 'svc_unexpected_response';
  static const svcNoProductId = 'svc_no_product_id';

  // ── Auction controller ──
  static const acWaitingApproval = 'ac_waiting_approval';
  static const acControlNeeded = 'ac_control_needed';
  static const acControlNeededBody = 'ac_control_needed_body';
  static const acPrimaryNeeded = 'ac_primary_needed';
  static const acPrimaryNeededBody = 'ac_primary_needed_body';
  static const acCouldNotAddProducts = 'ac_could_not_add_products';
  static const acSomethingWentWrong = 'ac_something_went_wrong';
  static const acHeadsUp = 'ac_heads_up';
  static const actStartStopFeed = 'act_start_stop_feed';
  static const actTakeStreamLive = 'act_take_stream_live';
  static const actEndStream = 'act_end_stream';
  static const actApproveMainRequests = 'act_approve_main_requests';
  static const actRejectMainRequests = 'act_reject_main_requests';
  static const actApproveControlRequests = 'act_approve_control_requests';
  static const actRejectControlRequests = 'act_reject_control_requests';
  static const slInvalidLink = 'sl_invalid_link';
  static const slInvalidLinkBody = 'sl_invalid_link_body';
  static const slCouldNotOpen = 'sl_could_not_open';
  static const slNoAppForUri = 'sl_no_app_for_uri';
  static const slOpenFailed = 'sl_open_failed';

  // ── Final sweep ──
  static const sasProduct = 'sas_product';
  static const sasStartingPrice = 'sas_starting_price';
  static const sasDutchPrice = 'sas_dutch_price';
  static const sasOriginalPrice = 'sas_original_price';
  static const rsThisDevice = 'rs_this_device';
  static const mtChest = 'mt_chest';
  static const mtWaist = 'mt_waist';
  static const mtShoulder = 'mt_shoulder';
  static const mtSleeveLength = 'mt_sleeve_length';
  static const mtArmLength = 'mt_arm_length';
  static const mtInseam = 'mt_inseam';
  static const mtTotalLength = 'mt_total_length';
  static const mtRise = 'mt_rise';
  static const mtWidth = 'mt_width';
  static const mtHeight = 'mt_height';
  static const mtDepth = 'mt_depth';
  static const mtOther = 'mt_other';
  static const mpCustomRtmp = 'mp_custom_rtmp';

  // ── Language picker ──
  static const languageRowTitle = 'language_row_title';
  static const languageRowSubtitle = 'language_row_subtitle';
  static const languageChanged = 'language_changed';

  // ── Email hints ──
  static const emailHintTommesalg = 'email_hint_tommesalg';
  static const emailHintExample = 'email_hint_example';
}
