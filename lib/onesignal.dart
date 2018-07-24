import 'dart:async';
import 'package:flutter/services.dart';
import 'package:OneSignalFlutter/src/permission.dart';
import 'package:OneSignalFlutter/src/subscription.dart';
import 'package:OneSignalFlutter/src/defines.dart';
import 'package:OneSignalFlutter/src/utils.dart';
import 'package:OneSignalFlutter/src/notification.dart';
import 'package:OneSignalFlutter/src/create_notification.dart';

export 'src/notification.dart';
export 'src/subscription.dart';
export 'src/permission.dart';
export 'src/defines.dart';
export 'src/create_notification.dart';

// Handlers for various events
typedef void ReceivedNotificationHandler(OSNotification notification);
typedef void OpenedNotificationHandler(OSNotificationOpenedResult openedResult);
typedef void SubscriptionChangedHandler(OSSubscriptionStateChanges changes);
typedef void EmailSubscriptionChangeHandler(OSEmailSubscriptionStateChanges changes);
typedef void PermissionChangeHandler(OSPermissionStateChanges changes);

class OneSignal {

  /// A singleton representing the OneSignal SDK.
  /// Note that the iOS and Android native libraries are static,
  /// so if you create multiple instances of OneSignal, they will
  /// mostly share the same state.
  static OneSignal shared = new OneSignal();

  // private channels used to bridge to ObjC/Java
  MethodChannel _channel = const MethodChannel('OneSignal');
  MethodChannel _tagsChannel = const MethodChannel('OneSignal#tags');
  
  // event handlers
  ReceivedNotificationHandler _onReceivedNotification;
  OpenedNotificationHandler _onOpenedNotification;
  SubscriptionChangedHandler _onSubscriptionChangedHandler;
  EmailSubscriptionChangeHandler _onEmailSubscriptionChangedHandler;
  PermissionChangeHandler _onPermissionChangedHandler;

  // constructor method
  OneSignal() {
    this._channel.setMethodCallHandler(_handleMethod);
  }

  /// The initializer for OneSignal. Note that this initializer
  /// accepts an iOSSettings object, in Android you can pass null.
  Future<void> init(String appId, {Map<OSiOSSettings, dynamic> iOSSettings}) async {
    _onesignalLog(OSLogLevel.verbose, "Initializing the OneSignal Flutter SDK ($sdkVersion)");
    
    var finalSettings = _processSettings(iOSSettings);

    await _channel.invokeMethod('OneSignal#init', { 
      'appId' : appId,
      'settings' : finalSettings
    });
  }

  /// Sets the log level for the SDK. The first parameter (logLevel) controls
  /// how verbose logs in the console/logcat are, while the visual log level
  /// controls if the SDK will show alerts for each logged message
  Future<void> setLogLevel(OSLogLevel logLevel, OSLogLevel visualLevel) async {
    await _channel.invokeMethod("OneSignal#setLogLevel", { 
      'console' : logLevel.index,
      'visual' : visualLevel.index
    });
  }

  /// The notification received handler will be called whenever a notification
  /// is received by the SDK (only applies to OneSignal push notifications)
  void setNotificationReceivedHandler(ReceivedNotificationHandler handler) {
    _onReceivedNotification = handler;
  }

  /// The notification opened handler is called whenever the user opens a 
  /// OneSignal push notification, or taps an action button on a notification.
  void setNotificationOpenedHandler(OpenedNotificationHandler handler) {
    _onOpenedNotification = handler;
  }

  /// The subscription handler will be called whenever the user's OneSignal
  /// subscription changes, such as when they are first assigned a 
  /// OneSignal user ID.
  void setSubscriptionObserver(SubscriptionChangedHandler handler) {
    _onSubscriptionChangedHandler = handler;
  }

  /// The permission handler will be called whenever the user's Permission
  /// state changes, which is applicable to iOS (Android does not prompt the
  /// user for permission to receive push notifications).
  void setPermissionObserver(PermissionChangeHandler handler) {
    _onPermissionChangedHandler = handler;
  }

  /// The email subscription handler will be called whenever the user's email
  /// subscription changes (OneSignal can also send emails in addition to push 
  /// notifications). For example, if you call setEmail() or logoutEmail().
  void setEmailSubscriptionObserver(EmailSubscriptionChangeHandler handler) {
    _onEmailSubscriptionChangedHandler = handler;
  }
  
  /// Allows you to completely disable the SDK until your app calls the 
  /// OneSignal.consentGranted(true) function. This is useful if you want
  /// to show a Terms and Conditions or privacy popup for GDPR.
  Future<void> setRequiresUserPrivacyConsent(bool required) async {
    await _channel.invokeMethod("OneSignal#setRequiresUserPrivacyConsent", {
      'required' : required
    });
  }

  /// If your application is set to require the user's consent before 
  /// using push notifications, your app should call this method when
  /// the user gives their consent. This will cause the OneSignal SDK 
  /// to initialize.
  Future<void> consentGranted(bool granted) async {
    await _channel.invokeMethod("OneSignal#consentGranted", {
      'granted' : granted
    });
  }

  /// A boolean value indicating if the OneSignal SDK is waiting for the 
  /// user's consent before it can initialize (if you set the app to
  /// require the user's consent)
  Future<bool> requiresUserPrivacyConsent() async {
    var val = await _channel.invokeMethod("OneSignal#requiresUserPrivacyConsent");
    
    return val as bool;
  }

  /// in iOS, will prompt the user for permission to send push notifications.
  Future<bool> promptUserForPushNotificationPermission({bool fallbackToSettings = false}) async {
    dynamic result = await _channel.invokeMethod("OneSignal#promptPermission", {
      'fallback' : fallbackToSettings
    });
    
    return result as bool;
  }

  /// in iOS, takes the user to the iOS Settings page for this app.
  Future<void> presentApplicationSettings() async {
    await _channel.invokeMethod("OneSignal#presentSettings");
  }

  /// The current setting that controls how notifications are displayed.
  Future<OSNotificationDisplayType> inFocusDisplayType() async {
    int type = await _channel.invokeMethod("OneSignal#inFocusDisplayType");
    return OSNotificationDisplayType.values[type];
  }

  Future<void> setInFocusDisplayType(OSNotificationDisplayType displayType) async {
    await _channel.invokeMethod("OneSignal#setInFocusDisplayType", {
      "displayType" : displayType.index
    });
  }

  /// Sends a single key/value pair to tags to OneSignal. 
  /// Please do not send hashmaps/arrays as values as this will fail.
  /// This method can often take more than five seconds to complete,
  /// so please do NOT block any user-interactive content while
  /// waiting for this request to complete.
  Future<Map<String, dynamic>> sendTag(dynamic key, dynamic value) async {
    Map<dynamic, dynamic> response = await this.sendTags({ key : value });
    return response.cast<String, dynamic>();
  }
  
  /// Updates the user's OneSignal tags. This method is additive
  /// This method can often take more than five seconds to complete,
  /// so please do NOT block any user-interactive content while
  /// waiting for this request to complete.
  Future<Map<String, dynamic>> sendTags(Map<dynamic, dynamic> tags) async {
    Map<dynamic, dynamic> response = await _tagsChannel.invokeMethod("OneSignal#sendTags", tags);
    return response.cast<String, dynamic>();
  }

  /// An asynchronous method that makes an HTTP request to OneSignal's
  /// API to retrieve the current user's tags.
  /// This request can take a while to complete: please do NOT block
  /// any user-interactive content while waiting for this request
  /// to finish.
  Future<Map<String, dynamic>> getTags() async {
    Map<dynamic, dynamic> tags = await _tagsChannel.invokeMethod("OneSignal#getTags");
    return tags.cast<String, dynamic>();
  }

  /// Allows you to delete a single key/value pair from the user's tags
  /// by specifying the key. This method can often take more than five 
  /// seconds to complete, so please do NOT block any user-interactive 
  /// content while waiting for this request to complete.
  Future<Map<String, dynamic>> deleteTag(String key) async {
    Map<dynamic, dynamic> response = await this.deleteTags([key]);
    return response.cast<String, dynamic>();
  }

  /// Allows you to delete an array of tags by specifying an
  /// array of keys.
  Future<Map<String, dynamic>> deleteTags(List<String> keys) async {
    Map<dynamic, dynamic> response = await _tagsChannel.invokeMethod("OneSignal#deleteTags", keys);
    return response.cast<String, dynamic>();
  }
  
  /// Returns an `OSPermissionSubscriptionState` object, which contains three properties:
  ///   1. `subscriptionStatus` : Describes the current user's OneSignal Push notification subscription
  ///   2. `emailSubscriptionStatus` : The current user's email subscription state
  ///   3. `permissionStatus` : The current user's permission, ie. have they answered the iOS permission prompt
  Future<OSPermissionSubscriptionState> getPermissionSubscriptionState() async {
    var json = await _channel.invokeMethod("OneSignal#getPermissionSubscriptionState");

    return OSPermissionSubscriptionState(json);
  }

  /// Allows you to manually disable or enable push notifications for this user.
  /// Note: This method does not change the user's system (iOS) push notification
  /// permission status. If the user disabled (or never allowed) your application
  /// to send push notifications, calling setSubscription(true) will not change that.
  Future<void> setSubscription(bool enable) async {
    await _channel.invokeMethod("OneSignal#setSubscription", enable);
  }

  /// Allows you to post a notification to the current user (or a different user 
  /// if you specify their OneSignal user ID).
  Future<Map<dynamic, dynamic>> postNotificationWithJson(Map<dynamic, dynamic> json) async {
    return await _channel.invokeMethod("OneSignal#postNotification", json);
  }

  Future<Map<dynamic, dynamic>> postNotification(OSCreateNotification notification) async {
    return await _channel.invokeMethod("OneSignal#postNotification", notification.mapRepresentation());
  }

  /// Allows you to prompt the user for permission to use location services
  Future<void> promptLocationPermission() async {
    return await _channel.invokeMethod("OneSignal#promptLocation");
  }

  /// Allows you to determine if the user's location data is shared with OneSignal.
  /// This allows you to do things like geofenced notifications, etc.
  Future<void> setLocationShared(bool shared) async {
    return await _channel.invokeMethod("OneSignal#setLocationShared", shared);
  }

  /// Sets the user's email so you can send them emails through the OneSignal dashboard
  /// and API. The `emailAuthHashToken` is optional (but highly recommended) as part of 
  /// Identity Verification. The email auth hash is a hash of your app's API key and the 
  /// user ID. We recommend you generate this token from your backend server, do NOT
  /// store your API key in your app as this is highly insecure.
  Future<void> setEmail({String email, String emailAuthHashToken}) async {
    return await _channel.invokeMethod("OneSignal#setEmail", {
      'email' : email,
      'emailAuthHashToken' : emailAuthHashToken
    });
  }

  /// Dissociates the user's email from OneSignal, akin to turning off push notifications 
  /// for email.
  Future<void> logoutEmail() async {
    return await _channel.invokeMethod("OneSignal#logoutEmail");
  }

  // Private function that gets called by ObjC/Java
  Future<Null> _handleMethod(MethodCall call) async {
    if (call.method == 'OneSignal#handleReceivedNotification' && this._onReceivedNotification != null) {
      return this._onReceivedNotification(OSNotification(call.arguments as Map<dynamic, dynamic>));
    } else if (call.method == 'OneSignal#handleOpenedNotification' && this._onOpenedNotification != null) {
      return this._onOpenedNotification(OSNotificationOpenedResult(call.arguments as Map<dynamic, dynamic>));
    } else if (call.method == 'OneSignal#subscriptionChanged' && this._onSubscriptionChangedHandler != null) {
      return this._onSubscriptionChangedHandler(OSSubscriptionStateChanges(call.arguments as Map<dynamic, dynamic>));
    } else if (call.method == 'OneSignal#permissionChanged' && this._onPermissionChangedHandler != null) {
      return this._onPermissionChangedHandler(OSPermissionStateChanges(call.arguments as Map<dynamic, dynamic>));
    } else if (call.method == 'OneSignal#emailSubscriptionChanged' && this._onEmailSubscriptionChangedHandler != null) {
      return this._onEmailSubscriptionChangedHandler(OSEmailSubscriptionStateChanges(call.arguments as Map<dynamic, dynamic>));
    }

    return null;
  }

  //PRIVATE METHODS
  Future<void> _onesignalLog(OSLogLevel level, String message) async {
    await _channel.invokeMethod("OneSignal#log", <String, dynamic> { 
      'logLevel' : level.index,
      'message' : message
    });
  }

  Map<String, dynamic> _processSettings(Map<OSiOSSettings, dynamic> settings) {
    var finalSettings = Map<String, dynamic>();

    for (OSiOSSettings key in settings.keys) {
      var settingsKey = convertEnumCaseToValue(key);
      var settingsValue = convertEnumCaseToValue(settings[key]);

      if (settingsKey == null) 
        continue;

      //we check if the value is also an enum case
      //ie. if they pass OSNotificationDisplayType,
      //we want to convert it to an integer before
      //passing the parameter to the ObjC bridge.
      finalSettings[settingsKey] = settingsValue ?? settings[key];
    }
    
    return finalSettings;
  }
}