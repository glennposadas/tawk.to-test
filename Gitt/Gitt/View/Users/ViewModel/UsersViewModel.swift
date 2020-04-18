//
//  UsersViewModel.swift
//  Gitt
//
//  Created by Glenn Von Posadas on 4/10/20.
//  Copyright © 2020 CitusLabs. All rights reserved.
//

import Foundation
import RxCocoa
import RxSwift

/**
 Protocol of `UsersViewModel`.
 */
protocol UsersDelegate: BaseViewModelDelegate {
    func showProfile(for user: User)
}

/**
 The viewmodel that the `UsersViewController` owns.
 */
class UsersViewModel: BaseViewModel {
    
    // MARK: - Properties
    
    private var queue = OperationQueue()
    
    /// The last seen user id.
    private var since: Int = 0
    private weak var delegate: UsersDelegate?
    
    var users = [User]()
    
    private var filteredUsers = [User]()
    private var filtering: Bool = false
    
    // MARK: Visibilities
    
    /// Should the loader be hidden?
    var loaderIsHidden = BehaviorRelay<Bool>(value: true)
    /// Should the tableView be hidden? I.e. hidden whilst loader is visible
    var tableViewIsHidden = BehaviorRelay<Bool>(value: true)
    
    // MARK: - Functions
    
    /// Function to re-do searching. Called by the refresh control
    override func refresh() {
        self.users.removeAll()
        self.loadUsers(since: 0)
    }
    
    /// Do searching... call `SearchService`.
    private func loadUsers(since: Int = 0) {
        if since == 0 {
            self.loaderIsHidden.accept(false)
            self.tableViewIsHidden.accept(true)
        }
        
        self.queue.cancelAllOperations()
        self.queue.qualityOfService = .background
        
        let block = BlockOperation {
            APIManager.GetUsers(parameters: ["since": since]).execute { (result) in
                self.loaderIsHidden.accept(true)
                self.tableViewIsHidden.accept(false)
                
                switch result {
                case let .success(newUsers):
                    newUsers.forEach { (newUser) in
                        self.users.append(newUser)
                    }
                    
                    self.since = newUsers.last?.id ?? 0
                    
                    DispatchQueue.main.async {
                        self.delegate?.reloadData()
                    }
                    
                case let .failure(error):
                    self.showError(error)
                }
            }
        }
        
        self.queue.addOperation(block)
    }
    
    // MARK: Overrides
    
    init(usersController: UsersDelegate?) {
        super.init()
        
        self.delegate = usersController
        
        self.queue.maxConcurrentOperationCount = 1
        
        self.loadUsers()
        
        // Be notified from internet status.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(self.refresh),
            name: AppNotificationName.refresh,
            object: nil
        )
    }
}

// MARK: - UITableViewDelegate

extension UsersViewModel: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        if self.filtering {
            if self.filteredUsers.count > indexPath.row {
                let user = self.filteredUsers[indexPath.row]
                self.delegate?.showProfile(for: user)
            }
        } else {
            if self.users.count > indexPath.row {
                let user = self.users[indexPath.row]
                self.delegate?.showProfile(for: user)
            }
        }
    }
}

// MARK: - UITableViewDataSource

extension UsersViewModel: UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell: UserTableViewCell?
        
        cell = tableView.dequeueReusableCell(withIdentifier: UserTableViewCell.identifier) as? UserTableViewCell
        
        if cell == nil {
            cell = UserTableViewCell()
        }
        
        let row = indexPath.row
        
        if self.filtering {
            if self.filteredUsers.count > row {
                let shouldInvert = row % 4 == 0 && row > 0
                let user = self.filteredUsers[indexPath.row]
                cell?.configure(with: user, invert: shouldInvert)
            }
        } else {
            if self.users.count > row {
                let shouldInvert = row % 4 == 0 && row > 0
                let user = self.users[indexPath.row]
                cell?.configure(with: user, invert: shouldInvert)
            }
        }
        
        return cell!
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.filtering ? self.filteredUsers.count : self.users.count
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        let lastItem = self.users.count - 1
        if indexPath.row == lastItem {
            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            spinner.frame = CGRect(x: CGFloat(0), y: CGFloat(0), width: tableView.bounds.width, height: CGFloat(44))
            tableView.tableFooterView = spinner
            
            self.loadUsers(since: self.since)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
                tableView.tableFooterView = nil
            }
        }
    }
}

// MARK: - UISearchResultsUpdating

extension UsersViewModel: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        if let text = searchController.searchBar.text, !text.isEmpty {
            self.filteredUsers = self.users.filter({ (user) -> Bool in
                let loginContains = user.login?.lowercased().contains(text.lowercased())
                let nameContains = user.name?.lowercased().contains(text.lowercased())
                return (loginContains == true || nameContains == true)
            })
            self.filtering = true
        } else {
            self.filtering = false
            self.filteredUsers = [User]()
        }
        
        self.delegate?.reloadData()
    }
}
