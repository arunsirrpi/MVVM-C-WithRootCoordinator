//
//  Coordinator.swift
//  MVVM-C-Take3
//
//  Created by Arun Sinthanaisirrpi on 25/1/2023.
//

import Foundation
import UIKit
import Combine
//MARK: - Type lifeted Navigation Step
protocol NavigationStep {}
//MARK: - PresentationMethods
enum PresentationMethod {
    case push(isAnimated: Bool)
    case present(isAnimated: Bool)
}

//MARK: - Bind the viewcontroller with coordinator to perform the flow logic
protocol ViewControllerNavigationBinding {
    var nextNavigationStepPublisher: AnyPublisher<NavigationStep?, Never> { get }
}
//MARK: - Coordinatable screen
protocol CoordinatableScreen {
    var screenID: UUID { get }
    var viewController: UIViewController { get }
}
//MARK: - Coordinator Protocol
protocol CoordinatorProtocol: AnyObject {
    associatedtype NavigationStepType: NavigationStep
    var screen: CoordinatableScreen { get }
    var navigationBindings: ViewControllerNavigationBinding? { get }
    var subscriptions: Set<AnyCancellable> { get set }
    func handleFlow(forNavigationStep: NavigationStepType)
}

extension CoordinatorProtocol {
    func setupRouting() {
        navigationBindings?
            .nextNavigationStepPublisher
            .compactMap { $0 as? NavigationStepType }
            .compactMap { $0 }
            .sink{ [weak self] navigationStep in
                self?.handleFlow(forNavigationStep: navigationStep)
            }
            .store(in: &subscriptions)
    }
    
    var navigationBindings: ViewControllerNavigationBinding? {
        screen.viewController as? ViewControllerNavigationBinding
    }
}

//MARK: - Root coordinator
protocol RootCoordinator: AnyObject {
    var navigationController: UINavigationController { get }
    var childCoordinators: [UUID: Any] { get set }
    var navigateToNewCoordinator: PassthroughSubject<(any CoordinatorProtocol)?, Never> { get }
    var childCoordinatorManagementSubscriptions: Set<AnyCancellable> { get set }
    var navigationStackObserver: NavigationStackObserverProtocol? { get }
}

extension RootCoordinator {
    func addChild(coordinator: any CoordinatorProtocol, withId id: UUID) {
        childCoordinators[id] = coordinator
    }
    
    func removeChild(withId id: UUID) {
        childCoordinators.removeValue(forKey: id)
    }
    
    func setupNavigationStackCleanup() {
        navigationStackObserver?
            .poppedViewControllerIDPublisher
            .compactMap { $0 }
            .sink { [weak self] uuid in
                self?.removeChild(withId: uuid)
            }
            .store(in: &childCoordinatorManagementSubscriptions)
        navigateToNewCoordinator
            .compactMap { $0 }
            .sink { [weak self] coordinator in
                self?.navigationController.pushViewController(coordinator.screen.viewController, animated: true)
                self?.addChild(coordinator: coordinator, withId: coordinator.screen.screenID)
            }
            .store(in: &childCoordinatorManagementSubscriptions)
    }
}

//MARK: - Navigation Stack for Routing
protocol NavigationStackObserverProtocol: AnyObject {
    var poppedViewControllerIDPublisher: AnyPublisher<UUID?, Never> { get }
}
/// Main purpose is to manage the routing
final class NavigationStackObserver: NSObject, UINavigationControllerDelegate, NavigationStackObserverProtocol {
    
    private(set) weak var navigationController: UINavigationController?
    @Published
    var poppedViewControllerID: UUID? = nil
    var poppedViewControllerIDPublisher: AnyPublisher<UUID?, Never> {
        $poppedViewControllerID.eraseToAnyPublisher()
    }
    
    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
        super.init()
        self.navigationController?.delegate = self
    }
    
    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        guard
            let fromViewController = navigationController.transitionCoordinator?.viewController(forKey: .from),
            navigationController.viewControllers.contains(fromViewController) == false,
            let poppedCoordinatableScreen = fromViewController as? CoordinatableScreen
        else {
            return
        }
        /// let the co-ordinator perform the clean up
        poppedViewControllerID = poppedCoordinatableScreen.screenID
    }
}

//MARK: - Implementation of Home root co-ordinator
//MARK: - Step 1: - Define the navigation routes from Home
enum NavigationStepsFromHome: CaseIterable, NavigationStep {
    case stationList
    case chromecast
    case settings
}
//MARK: - Step 2: - Define the home root coordinator
/// Root coordinator is one that will hold the navigation controller
/// this will allow us to observe the pops from the navigation controller
/// and we can clean the right child coordinaotr.
/// Inorder to manage the memory correctly, we need to
/// 1. Manage the coordinator child from the root
/// 2. Provide & Observe the navigation controller from the root
final class HomeRootCoordinator: CoordinatorProtocol, RootCoordinator {
    
    typealias NavigationStepType = NavigationStepsFromHome
    
    let screen: CoordinatableScreen = {
        let viewModel = ReusableDemoViewModel(
            name: "Root",
            backgroundColor: .gray
        )
        return ReusableDemoViewController(withViewModel: viewModel)
    }()
    
    let navigationController: UINavigationController
    let navigationStackObserver: NavigationStackObserverProtocol?
    var childCoordinators = [UUID : Any]()
    var navigationBindings: ViewControllerNavigationBinding? { screen as? ViewControllerNavigationBinding }
    var subscriptions = Set<AnyCancellable>()
    var childCoordinatorManagementSubscriptions = Set<AnyCancellable>()
    var navigateToNewCoordinator = PassthroughSubject<(any CoordinatorProtocol)?, Never>()
    
    //private(set) var pushedNewChildCoordinator = PassthroughSubject<(any CoordinatorProtocol)?, Never>()
    
    init() {
        navigationController = UINavigationController(rootViewController: screen.viewController)
        navigationStackObserver = NavigationStackObserver(navigationController: navigationController)
        setupRouting()
        setupNavigationStackCleanup()
    }
    
    func handleFlow(forNavigationStep navigationStep: NavigationStepsFromHome){
        let result: any CoordinatorProtocol
        switch navigationStep {
            case .stationList:
                result = StationListCoordinator(withChildCoordinatorAdded: navigateToNewCoordinator)
            case .settings:
                result = SettingsCoordinator(withChildCoordinatorAdded: navigateToNewCoordinator)
            case .chromecast:
                result = ChromecastCoordinator(withChildCoordinatorAdded: navigateToNewCoordinator)
        }
        navigateToNewCoordinator.send(result)
    }
}

//MARK: - Step 4: define the station list child coordinator
//MARK: - StationList coordinator
final class StationListCoordinator: CoordinatorProtocol {
    
    let screen: CoordinatableScreen = {
        let viewModel = ReusableDemoViewModel(
            name: "StationList",
            backgroundColor: .blue
        )
        return ReusableDemoViewController(withViewModel: viewModel)
    }()
    
    typealias NavigationStepType = NavigationStepsFromHome
    var subscriptions = Set<AnyCancellable>()
    weak var pushedNewChildCoordinator: PassthroughSubject<(any CoordinatorProtocol)?, Never>?
    
    init(withChildCoordinatorAdded onChildCoordinatorAdded: PassthroughSubject<(any CoordinatorProtocol)?, Never>?) {
        pushedNewChildCoordinator = onChildCoordinatorAdded
        setupRouting()
    }
    
    func handleFlow(forNavigationStep navigationStep: NavigationStepsFromHome) {
        let result: any CoordinatorProtocol
        switch navigationStep {
            case .stationList:
                result = StationListCoordinator(withChildCoordinatorAdded: pushedNewChildCoordinator)
            case .settings:
                result = SettingsCoordinator(withChildCoordinatorAdded: pushedNewChildCoordinator)
            case .chromecast:
                result = ChromecastCoordinator(withChildCoordinatorAdded: pushedNewChildCoordinator)
        }
        pushedNewChildCoordinator?.send(result)
    }
    
    deinit {
        print("StationListCoordinator deallocated")
    }
}

//MARK: - No navigation
enum NoNavigation: NavigationStep {}
//MARK: - Chromecast coordinator
final class ChromecastCoordinator: CoordinatorProtocol {
    let screen: CoordinatableScreen = {
        let viewModel = ReusableDemoViewModel(
            name: "Chromecast",
            backgroundColor: .green
        )
        return ReusableDemoViewController(withViewModel: viewModel)
    }()
    
    typealias NavigationStepType = NoNavigation
    var subscriptions = Set<AnyCancellable>()
    weak var pushedNewChildCoordinator: PassthroughSubject<(any CoordinatorProtocol)?, Never>?
    
    init(withChildCoordinatorAdded onChildCoordinatorAdded: PassthroughSubject<(any CoordinatorProtocol)?, Never>?) {
        pushedNewChildCoordinator = onChildCoordinatorAdded
        setupRouting()
    }
    
    /// No navigation from this endpoint
    func handleFlow(forNavigationStep: NoNavigation) {}
    
    deinit {
        print("ChromecastCoordinator deallocated")
    }
}

//MARK: - Settings coordinator
final class SettingsCoordinator: CoordinatorProtocol {
    let screen: CoordinatableScreen = {
        let viewModel = ReusableDemoViewModel(
            name: "Settings",
            backgroundColor: .systemPink
        )
        return ReusableDemoViewController(withViewModel: viewModel)
    }()
    
    typealias NavigationStepType = NoNavigation
    var subscriptions = Set<AnyCancellable>()
    weak var pushedNewChildCoordinator: PassthroughSubject<(any CoordinatorProtocol)?, Never>?
    
    init(withChildCoordinatorAdded onChildCoordinatorAdded: PassthroughSubject<(any CoordinatorProtocol)?, Never>?) {
        pushedNewChildCoordinator = onChildCoordinatorAdded
        setupRouting()
    }
    
    /// No navigation from this endpoint
    func handleFlow(forNavigationStep: NoNavigation) {}
    
    deinit {
        print("SettingsCoordinator deallocated")
    }
}
