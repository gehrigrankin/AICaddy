import Foundation
import HealthKit

/// Integrates with Apple Health to log golf workout data
@Observable
final class HealthKitService {
    var isAuthorized = false
    var stepsToday: Int?
    var distanceWalkedMiles: Double?
    var caloriesBurned: Int?

    private let store = HKHealthStore()
    private var workoutSession: HKWorkoutBuilder?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async {
        guard isAvailable else { return }

        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
        ]

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
        ]

        do {
            try await store.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            await MainActor.run { isAuthorized = true }
        } catch {
            await MainActor.run { isAuthorized = false }
        }
    }

    /// Start a golf workout session
    func startGolfWorkout() async {
        guard isAuthorized else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .golf
        config.locationType = .outdoor

        do {
            let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
            try await builder.beginCollection(at: Date())
            await MainActor.run { workoutSession = builder }
        } catch {
            print("Failed to start golf workout: \(error)")
        }
    }

    /// End the golf workout and save to Health
    func endGolfWorkout(totalCalories: Double? = nil, distanceMiles: Double? = nil) async {
        guard let builder = workoutSession else { return }

        do {
            // Add samples if available
            if let cal = totalCalories {
                let calSample = HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: cal),
                    start: builder.startDate ?? Date(),
                    end: Date()
                )
                try await builder.addSamples([calSample])
            }

            if let dist = distanceMiles {
                let distSample = HKQuantitySample(
                    type: HKQuantityType(.distanceWalkingRunning),
                    quantity: HKQuantity(unit: .mile(), doubleValue: dist),
                    start: builder.startDate ?? Date(),
                    end: Date()
                )
                try await builder.addSamples([distSample])
            }

            try await builder.endCollection(at: Date())
            try await builder.finishWorkout()
            await MainActor.run { workoutSession = nil }
        } catch {
            print("Failed to end golf workout: \(error)")
        }
    }

    /// Fetch today's step count for display
    func fetchTodaySteps() async {
        guard isAuthorized else { return }

        let stepsType = HKQuantityType(.stepCount)
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now)

        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: stepsType, predicate: predicate),
            options: .cumulativeSum
        )

        do {
            let result = try await descriptor.result(for: store)
            let steps = result?.sumQuantity()?.doubleValue(for: .count())
            await MainActor.run { stepsToday = steps.map(Int.init) }
        } catch {
            // silently fail
        }
    }

    /// Estimate calories burned during a golf round
    /// Average is ~300-400 calories per 9 holes walking
    static func estimateCalories(holes: Int, isWalking: Bool) -> Double {
        let perHole = isWalking ? 38.0 : 20.0  // walking vs cart
        return Double(holes) * perHole
    }
}
