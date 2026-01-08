// Can be generated automatically with
// curl -s https://ip-ranges.amazonaws.com/ip-ranges.json | jq ".prefixes[].region" | sort | uniq

// or use https://github.com/boto/botocore/blob/develop/botocore/data/endpoints.json

public struct Region: Sendable, RawRepresentable, Equatable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    // Africa (Cape Town)
    public static var afsouth1: Region { .init(rawValue: "af-south-1") }
    // Asia Pacific (Hong Kong)
    public static var apeast1: Region { .init(rawValue: "ap-east-1") }
    // Asia Pacific (Tokyo)
    public static var apnortheast1: Region { .init(rawValue: "ap-northeast-1") }
    // Asia Pacific (Seoul)
    public static var apnortheast2: Region { .init(rawValue: "ap-northeast-2") }
    // Asia Pacific (Osaka)
    public static var apnortheast3: Region { .init(rawValue: "ap-northeast-3") }
    // Asia Pacific (Mumbai)
    public static var apsouth1: Region { .init(rawValue: "ap-south-1") }
    // Asia Pacific (Hyderabad)
    public static var apsouth2: Region { .init(rawValue: "ap-south-2") }
    // Asia Pacific (Singapore)
    public static var apsoutheast1: Region { .init(rawValue: "ap-southeast-1") }
    // Asia Pacific (Sydney)
    public static var apsoutheast2: Region { .init(rawValue: "ap-southeast-2") }
    // Asia Pacific (Jakarta)
    public static var apsoutheast3: Region { .init(rawValue: "ap-southeast-3") }
    // Asia Pacific (Melbourne)
    public static var apsoutheast4: Region { .init(rawValue: "ap-southeast-4") }
    // Canada (Central)
    public static var cacentral1: Region { .init(rawValue: "ca-central-1") }
    // Canada West (Calgary)
    public static var cawest1: Region { .init(rawValue: "ca-west-1") }
    // China (Beijing)
    public static var cnnorth1: Region { .init(rawValue: "cn-north-1") }
    // China (Ningxia)
    public static var cnnorthwest1: Region { .init(rawValue: "cn-northwest-1") }
    // Europe (Frankfurt)
    public static var eucentral1: Region { .init(rawValue: "eu-central-1") }
    // Europe (Zurich)
    public static var eucentral2: Region { .init(rawValue: "eu-central-2") }
    // Europe (Stockholm)
    public static var eunorth1: Region { .init(rawValue: "eu-north-1") }
    // Europe (Milan)
    public static var eusouth1: Region { .init(rawValue: "eu-south-1") }
    // Europe (Spain)
    public static var eusouth2: Region { .init(rawValue: "eu-south-2") }
    // Europe (Ireland)
    public static var euwest1: Region { .init(rawValue: "eu-west-1") }
    // Europe (London)
    public static var euwest2: Region { .init(rawValue: "eu-west-2") }
    // Europe (Paris)
    public static var euwest3: Region { .init(rawValue: "eu-west-3") }
    // Middle East (UAE)
    public static var mecentral1: Region { .init(rawValue: "me-central-1") }
    // Middle East (Bahrain)
    public static var mesouth1: Region { .init(rawValue: "me-south-1") }
    // South America (Sao Paulo)
    public static var saeast1: Region { .init(rawValue: "sa-east-1") }
    // US East (N. Virginia)
    public static var useast1: Region { .init(rawValue: "us-east-1") }
    // US East (Ohio)
    public static var useast2: Region { .init(rawValue: "us-east-2") }
    // AWS GovCloud (US-East)
    public static var usgoveast1: Region { .init(rawValue: "us-gov-east-1") }
    // AWS GovCloud (US-West)
    public static var usgovwest1: Region { .init(rawValue: "us-gov-west-1") }
    // US ISO East
    public static var usisoeast1: Region { .init(rawValue: "us-iso-east-1") }
    // US ISO WEST
    public static var usisowest1: Region { .init(rawValue: "us-iso-west-1") }
    // US ISOB East (Ohio)
    public static var usisobeast1: Region { .init(rawValue: "us-isob-east-1") }
    // US West (N. California)
    public static var uswest1: Region { .init(rawValue: "us-west-1") }
    // US West (Oregon)
    public static var uswest2: Region { .init(rawValue: "us-west-2") }
    // other region
    public static func other(_ name: String) -> Region { .init(rawValue: name) }
}

extension Region: CustomStringConvertible {
    public var description: String { self.rawValue }
}

extension Region: Codable {}

// allows to create a Region from a String
// it will only create a Region if the provided
// region name is valid.
extension Region {
    public init?(awsRegionName: String) {
        self.init(rawValue: awsRegionName)
        switch self {
        case .afsouth1,
            .apeast1,
            .apnortheast1,
            .apnortheast2,
            .apnortheast3,
            .apsouth1,
            .apsouth2,
            .apsoutheast1,
            .apsoutheast2,
            .apsoutheast3,
            .apsoutheast4,
            .cacentral1,
            .cawest1,
            .cnnorth1,
            .cnnorthwest1,
            .eucentral1,
            .eucentral2,
            .eunorth1,
            .eusouth1,
            .eusouth2,
            .euwest1,
            .euwest2,
            .euwest3,
            .mecentral1,
            .mesouth1,
            .saeast1,
            .useast1,
            .useast2,
            .usgoveast1,
            .usgovwest1,
            .usisoeast1,
            .usisowest1,
            .usisobeast1,
            .uswest1,
            .uswest2:
            return
        default:
            return nil
        }
    }
}
