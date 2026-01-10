import Foundation
import simd

/// Geometry helpers for converting angular coordinates to 3D positions
/// Used for placing stimuli on a fixed-radius "virtual bowl" (spherical surface)
struct PeripheralGeometry {

    /// Converts angular coordinates to a 3D position on a sphere at fixed radius
    /// - Parameters:
    ///   - eccentricityDeg: Degrees away from fixation (0 = center/fixation, positive = outward)
    ///   - polarAngleDeg: Direction around fixation in degrees (0 = right, 90 = up, 180 = left, 270 = down)
    ///   - radius: Distance from the eye/origin in meters
    /// - Returns: 3D position (SIMD3<Float>) in world coordinates
    ///
    /// Coordinate system:
    /// - +X = right
    /// - +Y = up
    /// - -Z = forward (into the screen, where user looks)
    static func angularToPosition(eccentricityDeg: Float, polarAngleDeg: Float, radius: Float) -> SIMD3<Float> {
        // Convert degrees to radians
        let eccentricityRad = eccentricityDeg * .pi / 180.0
        let polarAngleRad = polarAngleDeg * .pi / 180.0

        // Spherical to Cartesian conversion
        // For VisionOS coordinate system where -Z is forward:
        // - Start with point at (0, 0, -radius) looking straight ahead
        // - Rotate by eccentricity angle (how far from center)
        // - Rotate by polar angle (which direction around the circle)

        let x = radius * sin(eccentricityRad) * cos(polarAngleRad)
        let y = radius * sin(eccentricityRad) * sin(polarAngleRad)
        let z = -radius * cos(eccentricityRad)

        return SIMD3<Float>(x, y, z)
    }

    /// Converts a 3D position to angular coordinates
    /// Useful for analyzing where a stimulus was placed
    /// - Parameters:
    ///   - position: 3D position in world coordinates
    ///   - radius: Expected radius (distance from origin)
    /// - Returns: Tuple of (eccentricity in degrees, polar angle in degrees)
    static func positionToAngular(position: SIMD3<Float>, radius: Float) -> (eccentricityDeg: Float, polarAngleDeg: Float) {
        // Calculate actual radius
        let actualRadius = length(position)

        // Calculate eccentricity (angle from -Z axis)
        let eccentricityRad = acos(-position.z / actualRadius)
        let eccentricityDeg = eccentricityRad * 180.0 / .pi

        // Calculate polar angle (direction in XY plane)
        let polarAngleRad = atan2(position.y, position.x)
        let polarAngleDeg = polarAngleRad * 180.0 / .pi

        return (eccentricityDeg, polarAngleDeg)
    }

    /// Common fixation point position (center of visual field)
    /// - Parameter distance: Distance from the eye in meters
    /// - Returns: Position for central fixation point
    static func fixationPosition(distance: Float) -> SIMD3<Float> {
        return SIMD3<Float>(0, 0, -distance)
    }

    /// Converts angular diameter (degrees) to physical diameter (meters) at a given radius
    /// Used for sizing stimuli on the spherical bowl
    /// - Parameters:
    ///   - angularDiameterDeg: Angular size in degrees (e.g., 0.43° for Goldmann III)
    ///   - radius: Distance from eye to stimulus in meters
    /// - Returns: Physical diameter in meters
    ///
    /// Formula: diameter = 2 * radius * tan(angularDiameter / 2)
    /// For small angles, this is approximately: diameter ≈ radius * angularDiameter_radians
    static func angularDiameterToPhysical(angularDiameterDeg: Float, radius: Float) -> Float {
        let angularDiameterRad = angularDiameterDeg * .pi / 180.0
        // Exact formula for chord length on sphere
        let physicalDiameter = 2.0 * radius * tan(angularDiameterRad / 2.0)
        return physicalDiameter
    }

    /// Converts physical diameter (meters) to angular diameter (degrees) at a given radius
    /// Inverse of angularDiameterToPhysical
    /// - Parameters:
    ///   - physicalDiameter: Physical size in meters
    ///   - radius: Distance from eye in meters
    /// - Returns: Angular size in degrees
    static func physicalDiameterToAngular(physicalDiameter: Float, radius: Float) -> Float {
        let angularDiameterRad = 2.0 * atan(physicalDiameter / (2.0 * radius))
        let angularDiameterDeg = angularDiameterRad * 180.0 / .pi
        return angularDiameterDeg
    }
}
