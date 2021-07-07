//
//  MAURLocation+Extension.swift
//  COVIDSafePaths
//
//  Created by Michael Neas on 5/21/20.
//  Copyright © 2020 Path Check Inc. All rights reserved.
//
import Foundation
import Scrypt

extension MAURLocation {

  // Require a timestamp and non (0, 0) (lat, lon). Would name `isValid` but this conflicts with existing prop.
  @objc public var isAcceptable: Bool {
    return hasTime() && (abs(latitude.doubleValue) > 1e-5 || abs(longitude.doubleValue) > 1e-5)
  }

  /// Generates array of geohashes concatenated with time, within a 10 meter radius of given location
  public var geoHashes: [String] {
    Geohash.GEO_CIRCLE_RADII.map({ radii in
      (latitude.doubleValue + radii.latitude, longitude.doubleValue + radii.longitude)
    }).reduce(into: Set<String>(), { (hashes, currentLocation) in
      hashes.insert(Geohash.encode(latitude: currentLocation.0, longitude: currentLocation.1, length: 8))
    }).reduce(into: [String](), { (hashes, hash) in
      let timeWindow = timeWindows(interval: 60 * 5 * 1000)
      hashes.append("\(hash)\(timeWindow.early)")
      hashes.append("\(hash)\(timeWindow.late)")
    })
  }

  /// Encodes geoHashes with the scrypt algorithm
  public var scryptHashes: [String] {
    let start = DispatchTime.now()
    let scryptGeoHashes = geoHashes.map(scrypt)
    let end = DispatchTime.now()

    let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
    let timeInterval = Double(nanoTime) / 1_000_000_000

    Log.scryptHashing.debug(String(format: "Hashing completed in: %.4f seconds", timeInterval))

    return scryptGeoHashes
  }

  convenience init(location: Location) {
    self.init()
    time = location.date
    latitude = location.latitude as NSNumber
    longitude = location.longitude as NSNumber
    accuracy = location.accuracy.value as NSNumber?
    altitude = location.altitude.value as NSNumber?
    altitudeAccuracy = location.altitudeAccuracy.value as NSNumber?
    speed = location.speed.value as NSNumber?
    heading = location.bearing.value as NSNumber?
  }

  /// Generates rounded time windows for interval before and after timestamp
  /// - Parameters:
  ///   - interval: location storage interval in milliseconds
  public func timeWindows(interval: Int64) -> (early: Int64, late: Int64) {
    let ms = Int64(time.timeIntervalSince1970 * 1000.0)

    let early = (ms - interval / 2) / interval * interval
    let late = (ms + interval / 2) / interval * interval

    return (early, late)
  }

  /// Apply scrypt hash algorithm on a String
  ///
  /// - Parameters:
  ///     - hash: value to hash
  public func scrypt(on hash: String) -> String {
    let hash = Array(hash.utf8)
    let generic = Array("salt".utf8)
    ///  A “cost” (N) that is to be determined.  Initially was 16384, then modified to 4096
    ///  A salt of “salt”
    ///  A block size of 8
    ///  A keylen (output) of 8 bytes = 16 hex digits.
    /// Parallelization (p) of 1 - this is the default.
    return try! Scrypt.scrypt(password: hash, salt: generic, length: 8,N: 4096, r: 8, p: 1).toHexString()
  }
}
