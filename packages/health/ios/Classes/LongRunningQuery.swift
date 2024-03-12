//
//  LongRunningQuery.swift
//  Runner
//
//  Created by Yauhen Sampir on 1/3/24.
//

import Flutter
import Foundation
import HealthKit

import UIKit
import UserNotifications

public class LongRunningQuery: NSObject, FlutterStreamHandler, FlutterPlugin {
    private let typesToReadKey = "health_types_to_read"
    private let backgroundCallbackHandleIDKey = "healthKit_callback_handle"
    
    private var eventSink: FlutterEventSink?
    private var engine: FlutterEngine?
    private var isEngineRunning = false
    private var eventChannel: FlutterEventChannel?
    private var typesToSend: Set<String> = []
    private var _queryList: [HKQuery] = []
    private static var pluginRegistrant: ((FlutterEngine) -> Void)?
    
    public static func initialize(with registrar: FlutterPluginRegistrar, using pluginRegistrant: @escaping (FlutterEngine) -> Void) {
        self.pluginRegistrant = pluginRegistrant
        LongRunningQuery.register(with: registrar)
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        NSLog("PLUGIN REGISTERED")
        
        let channel = FlutterMethodChannel(
            name: "health_kit_background_service",
            binaryMessenger: registrar.messenger(),
            codec: FlutterJSONMethodCodec()
        )
        
        let instance = LongRunningQuery()
        instance.run()
        
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "configure" {
            let arguments = call.arguments as? [String: Any]
            
            let types = arguments?["types"] as! [String]
            let backgroundCallbackHandleID = arguments?["handle"] as? NSNumber
            
            UserDefaults.standard.set(backgroundCallbackHandleID?.int64Value, forKey: backgroundCallbackHandleIDKey)
            UserDefaults.standard.set(types, forKey: typesToReadKey)
            run()
            
            result(true)
        } else if call.method == "stop_service" {
            UserDefaults.standard.removeObject(forKey: backgroundCallbackHandleIDKey)
            UserDefaults.standard.removeObject(forKey: typesToReadKey)
            
            let store = HKHealthStore()
            for query in _queryList {
                store.stop(query)
                engine?.destroyContext()
            }
            _queryList.removeAll()
            isEngineRunning = false
            NSLog("SERVICE STOPPED")
            result(true)
        }
    }
    
    func buildEngine() {
        engine = FlutterEngine(name: "health_kit_background_engine", project: nil, allowHeadlessExecution: true)
        if let newEngine = engine {
            eventChannel = FlutterEventChannel(name: "health_kit_background_service_channel", binaryMessenger: newEngine.binaryMessenger)
        }
    }
    
    func run() {
        if isEngineRunning {
            return
        }
        
        let defaults = UserDefaults.standard
        guard let callbackHandle = defaults.object(forKey: backgroundCallbackHandleIDKey) as? Int64 else {
            NSLog("NO CALLBACK HANDLER")
            return
        }
        
        guard let healthTypes = defaults.array(forKey: typesToReadKey) as? [String] else {
            NSLog("NO HEALTH TYPES FOUND")
            return
        }
        
        var sampleTypes = [String: HKSampleType]()
        let swiftHealthPlugin = SwiftHealthPlugin()
        
        for type in healthTypes {
            sampleTypes[type] = swiftHealthPlugin.dataTypeLookUp(key: type)
        }
        
        NSLog("TRYING TO START ENGINE")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.buildEngine()
            if let engine = self.engine, let eventChannel = self.eventChannel {
                self.isEngineRunning = engine.run(withEntrypoint: "healthKitEntryPoint", libraryURI: "package:health/health.dart", initialRoute: nil, entrypointArgs: [String(callbackHandle)])
                LongRunningQuery.pluginRegistrant?(engine)
                
                if self.isEngineRunning {
                    eventChannel.setStreamHandler(self)
                    self.subscribe(sampleTypes: sampleTypes)
                }
            }
        }
    }
    
    func subscribe(sampleTypes: [String: HKSampleType]) {
        // Create the types we want to read and write
        let store = HKHealthStore()
        
        //let localNotificationManager = LocalNotificationManager()
        //localNotificationManager.requestPermission { _, _ in }
        
        store.requestAuthorization(toShare: [], read: Set(sampleTypes.values)) { [weak self] _, _ in
            for sampleTypeKeyValue in sampleTypes {
                let sampleType = sampleTypeKeyValue.value
                
                let query = HKObserverQuery(
                    sampleType: sampleType, predicate: nil
                ) { query, completion, _ in
//                    guard let identifier = query.objectType?.identifier else { return }
//                    let notification = LocalNotification(
//                        title: "I FOUND, FOUND",
//                        subtitle: "\(String(describing: identifier))"
//                    )
//                        
//                    localNotificationManager.scheduleNotification(notification)
                                        
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        self.eventSink?(sampleTypeKeyValue.key)
                    }
                    
                    completion()
                }
                store.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { success, error in
                    NSLog("Background delivery \(success) for \(sampleType) error: \(String(describing: error))")
                }
                store.execute(query)
                self?._queryList.append(query)
            }
        }
    }

    public func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        NSLog("ONLISTEN")
        self.eventSink = eventSink
        
        for type in typesToSend {
            eventSink(type)
        }
        
        typesToSend.removeAll()

        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        return nil
    }
}

//struct LocalNotification {
//    let title: String
//    let subtitle: String
//}

//class LocalNotificationManager {
//    func requestPermission(completionHandler: @escaping (Bool, Error?) -> Void) {
//        UNUserNotificationCenter.current().requestAuthorization(
//            options: [
//                .alert,
//                .badge,
//                .sound
//            ],
//            completionHandler: completionHandler
//        )
//    }
//
//    func scheduleNotification(_ notification: LocalNotification) {
//        let content = UNMutableNotificationContent()
//        content.title = notification.title
//        content.subtitle = notification.subtitle
//        content.sound = UNNotificationSound.default
//        let trigger = UNTimeIntervalNotificationTrigger(
//            timeInterval: 1,
//            repeats: false
//        )
//        let request = UNNotificationRequest(
//            identifier: UUID().uuidString,
//            content: content,
//            trigger: trigger
//        )
//        UNUserNotificationCenter.current().add(request)
//    }
//}
