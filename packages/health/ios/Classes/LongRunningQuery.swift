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
    
    private var eventSink: FlutterEventSink?
    private var eventChannel: FlutterEventChannel?
    private var typesToSend: Set<String> = []
    private var _queryList: [HKQuery] = []
    
    public static func initialize(with registrar: FlutterPluginRegistrar) {
        LongRunningQuery.register(with: registrar)
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        NSLog("PLUGIN REGISTERED")
        
        let instance = LongRunningQuery()
        
        instance.eventChannel = FlutterEventChannel(name: "health_kit_background_service_channel", binaryMessenger: registrar.messenger())
        instance.eventChannel?.setStreamHandler(instance)
        
        let channel = FlutterMethodChannel(
            name: "health_kit_background_service",
            binaryMessenger: registrar.messenger(),
            codec: FlutterJSONMethodCodec()
        )
        
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)
    }
        
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "configure" {
            let arguments = call.arguments as? [String: Any]
            let types = arguments?["types"] as! [String]
            UserDefaults.standard.set(types, forKey: typesToReadKey)
            result(true)
        } else if call.method == "stop_service" {
            stopService()
            result(true)
        } else if call.method == "start_service" {
            startService()
            result(true)
        }
    }
    
    func startService(){
        let defaults = UserDefaults.standard
        
        guard let healthTypes = defaults.array(forKey: typesToReadKey) as? [String] else {
            NSLog("NO HEALTH TYPES FOUND")
            return
        }
        
        var sampleTypes = [String: HKSampleType]()
        let swiftHealthPlugin = SwiftHealthPlugin()
        swiftHealthPlugin.initializeTypes()
        
        for type in healthTypes {
            sampleTypes[type] = swiftHealthPlugin.dataTypeLookUp(key: type)
        }
        
        subscribe(sampleTypes: sampleTypes)
        NSLog("SERVICE STARTED")
    }
    
    func stopService(){
        UserDefaults.standard.removeObject(forKey: typesToReadKey)
        
        let store = HKHealthStore()
        for query in _queryList {
            store.stop(query)
        }
        _queryList.removeAll()
        NSLog("SERVICE STOPPED")
    }
    
    func subscribe(sampleTypes: [String: HKSampleType]) {
        // Create the types we want to read and write
        let store = HKHealthStore()
        
        store.requestAuthorization(toShare: [], read: Set(sampleTypes.values)) { [weak self] _, _ in
            for sampleTypeKeyValue in sampleTypes {
                let sampleType = sampleTypeKeyValue.value
                
                let query = HKObserverQuery(
                    sampleType: sampleType, predicate: nil
                ) { query, completion, _ in
                    guard let identifier = query.objectType?.identifier else { return }

                    DispatchQueue.main.async { self?.eventSink?(sampleTypeKeyValue.key) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                        completion()
                    }
                    
                }
                store.execute(query)
                store.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { success, error in
                    NSLog("Background delivery \(success) for \(sampleType) error: \(String(describing: error))")
                }
                
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
