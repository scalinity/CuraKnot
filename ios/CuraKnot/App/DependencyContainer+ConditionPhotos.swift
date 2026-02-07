import Foundation
import ObjectiveC

private var photoStorageManagerKey: UInt8 = 0
private var conditionPhotoServiceKey: UInt8 = 0

extension DependencyContainer {
    var photoStorageManager: PhotoStorageManager {
        if let cached = objc_getAssociatedObject(self, &photoStorageManagerKey) as? PhotoStorageManager {
            return cached
        }
        let manager: PhotoStorageManager
        do {
            manager = try PhotoStorageManager()
        } catch {
            fatalError("Failed to initialize PhotoStorageManager: \(error)")
        }
        objc_setAssociatedObject(self, &photoStorageManagerKey, manager, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return manager
    }

    var conditionPhotoService: ConditionPhotoService {
        if let cached = objc_getAssociatedObject(self, &conditionPhotoServiceKey) as? ConditionPhotoService {
            return cached
        }
        let service = ConditionPhotoService(
            supabaseClient: supabaseClient,
            subscriptionManager: subscriptionManager,
            photoStorageManager: photoStorageManager,
            authManager: authManager
        )
        objc_setAssociatedObject(self, &conditionPhotoServiceKey, service, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return service
    }
}
