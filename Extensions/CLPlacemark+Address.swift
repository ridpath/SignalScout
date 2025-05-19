import CoreLocation

extension CLPlacemark {
    /// Returns a compact, comma-separated address string
    var compactAddress: String {
        [subThoroughfare,
         thoroughfare,
         locality,
         administrativeArea,
         postalCode,
         country]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
