//
//  MapViewController.swift
//  Charge_Map
//
//  Created by Macbook pro on 20/11/2019.
//  Copyright © 2019 Macbook pro. All rights reserved.
//

import UIKit
import MapKit
import CoreLocation

class MapViewController: UIViewController, SettingsDelegate {
    
    // MARK: - IBOutlets
    @IBOutlet weak var mapView: MKMapView!
    
    // MARK: Properties
    let apiHelper = ApiHelper()
    let annotationManager = AnnotationManager()
    let userLocationManager = CLLocationManager()
    var recordsWithoutDuplicates: [Record?] = []
    
    var lastLocation: CLLocationCoordinate2D? = nil {
        willSet {
            if newValue != nil {
                getAnnotations(userPosition: newValue)
            }
        }
    }
    
    // MARK: Life Cycle Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        addNotificationWillEnterForeground()
        setupController()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        navigationController?.navigationBar.isHidden = true
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setupUserLocation()
    }
    
    // IBActions
    @IBAction func showSettingViewController(_ sender: UIButton) {
        performSegue(withIdentifier: "mapVCToSettingVC", sender: nil)
    }
    
    @IBAction func showTableView(_ sender: UIButton) {
        guard !annotationManager.annotations.isEmpty else { return }
        performSegue(withIdentifier: Word.mapVCToTableVC, sender: nil)
    }
    
    
    // MARK: Setup & Settings Methods
    // Setup coordinates user, mapView, launch request and display annotations
    fileprivate func addNotificationWillEnterForeground() {
        let notifName = UIApplication.willEnterForegroundNotification
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(appEnterInForeground), name: notifName, object: nil)
    }
    
    private func setupController() {
        mapView.mapType = .hybridFlyover
        mapView.register(CustomAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
    }
    
    private func updateMapView() {
        DispatchQueue.main.async {
            self.mapView.removeAllAnnotations()
            self.mapView.showsUserLocation = true
            self.mapView.addAnnotations(self.annotationManager.annotations)
            self.mapView.showAllAnnotations()
        }
    }
    
    private func createAllAnnotations() {
        for annotation in self.recordsWithoutDuplicates {
            if let annotation = annotation {
                self.annotationManager.createAnnotation(annotation: annotation)
            }
        }
    }
    
    private func addGeoFilterIfUserPositionIsNotNil(_ userPosition: CLLocationCoordinate2D?) {
        if let userPosition = userPosition {
            apiHelper.addGeofilterUrl(latitude: "\(userPosition.latitude)", longitude: "\(userPosition.longitude)")
        }
    }
    
    // MARK: - Network Call
    func getAnnotations(userPosition: CLLocationCoordinate2D?) {
        
        annotationManager.annotations.removeAll()
        mapView.removeAllAnnotations()
        
        addGeoFilterIfUserPositionIsNotNil(userPosition)
        
        apiHelper.getAnnotations { (success, result) in
            
            guard success, let result = result else { return print("problem") }
            
            self.recordsWithoutDuplicates = self.apiHelper.removeDuplicateRecords(result: result, annotationManager: self.annotationManager)
            self.createAllAnnotations()
            self.updateMapView()
        }
    }
}
    
// MARK: MKMapViewDelegate
extension MapViewController: MKMapViewDelegate {
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if let cluster = annotation as? MKClusterAnnotation {
            if let firstAnnot = cluster.memberAnnotations.first as? CustomAnnotation {
                let customAnnotationView = CustomAnnotationView(annotation: firstAnnot, reuseIdentifier: firstAnnot.type.rawValue)
                customAnnotationView.displayPriority = .required
                return customAnnotationView
            }
        }
        
        return mapView.view(for: annotation)
    }
    
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        
        if let cluster = view.annotation as? MKClusterAnnotation {
            mapView.showAnnotations(cluster.memberAnnotations, animated: true)
        } else {
            guard let annotation = view.annotation as? CustomAnnotation else { return }
            annotationManager.annotationSelected = annotation
            annotationManager.coordinatesSelectedAnnotation = view.annotation?.coordinate
            performSegue(withIdentifier: Word.mapVCToDetailVC, sender: nil)
        }
    }
}

// MARK: - Navigation
extension MapViewController {
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == Word.mapVCToDetailVC,
            let detailVC = segue.destination as? DetailViewController {
            
            if let annotationSelected = annotationManager.annotationSelected {
                if let fieldAnnotationSelected = annotationSelected.field {
                    detailVC.fields = []
                    detailVC.fields.append(fieldAnnotationSelected)
                    detailVC.apiHelper = apiHelper
                    detailVC.annotationManager = annotationManager
                }
            }
        } else if segue.identifier == Word.mapVCToTableVC, let tableVC = segue.destination as? TableViewController {
            tableVC.annotationManager = annotationManager
        } else if segue.identifier == "mapVCToSettingVC", let settingVC = segue.destination as? SettingViewController {
            
        }
    }
}

// MARK: LocationManagerDelegate
extension MapViewController: CLLocationManagerDelegate, RedirectionDelegate {
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switchAuthorizationStatusToExecuteAction(status)
    }
    
    private func switchAuthorizationStatusToExecuteAction(_ status: CLAuthorizationStatus) {
        switch status {
            case .notDetermined:
                userLocationManager.requestWhenInUseAuthorization()
            
            case .restricted:
                presentAlertToRestrictedCase()
            
            case .denied:
                presentAlertToDeniedCase()
            
            case .authorizedAlways, .authorizedWhenInUse:
                userLocationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
                userLocationManager.startUpdatingLocation()
            
            @unknown default:
                break
        }
    }
    
    private func presentAlertToRestrictedCase() {
        if annotationManager.annotations.isEmpty && locationServiceIsEnabled() == false {
            presentAlert(showCancelAction: false)
        } else if annotationManager.annotations.isEmpty == false && locationServiceIsEnabled() == false {
            presentAlert(showCancelAction: true)
        }
    }
    
    private func presentAlertToDeniedCase() {
        if annotationManager.annotations.isEmpty {
            presentAlert(showCancelAction: false)
        } else {
            presentAlert(showCancelAction: true)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        updateCoordinateUserAndStopUpdating(locations)
    }
    
    private func updateCoordinateUserAndStopUpdating(_ locations: [CLLocation]) {
        if let lastCoordinate = locations.first?.coordinate, lastLocation == nil {
            lastLocation = lastCoordinate
            Datas.coordinateUser = lastCoordinate
            userLocationManager.stopUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Impossible de trouver l'emplacement de l'utilisateur: \(error.localizedDescription)")
    }
    
}

// Mark: - Setups and Settings
extension MapViewController {
    
    func setupUserLocation() {
        lastLocation = nil
        userLocationManager.delegate = self
        if CLLocationManager.locationServicesEnabled() && CLLocationManager.authorizationStatus() != .denied {
            userLocationManager.requestWhenInUseAuthorization()
            userLocationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            userLocationManager.startUpdatingLocation()
        } else {
            presentAlert(showCancelAction: false)
        }
    }
    
    @objc func appEnterInForeground() {
        if annotationManager.annotations.isEmpty && locationServiceIsEnabled() == true {
            setupUserLocation()
        } else if annotationManager.annotations.isEmpty && locationServiceIsEnabled() == false {
            presentAlert(showCancelAction: false)
        } else if annotationManager.annotations.isEmpty == false && locationServiceIsEnabled() == false {
            presentAlert(showCancelAction: true)
        } else if annotationManager.annotations.isEmpty == false && locationServiceIsEnabled() == true {
            return
        }
    }
    
}


// MARK: - ALERTS
extension MapViewController {
    
    func presentAlert(showCancelAction: Bool) {
        let alertController = UIAlertController(title: "Position non detectée", message: "Veuillez activer votre position.", preferredStyle: .actionSheet)
        let action1 = UIAlertAction(title: "Récupèrer toutes les annotations", style: .default) { (_) in
            self.getAnnotations(userPosition: nil)
        }
        
        let action2 = UIAlertAction(title: "Accéder aux réglages", style: .default) { (_) in
            self.redirectingToLocationSettings()
        }
        
        let action3 = UIAlertAction(title: "Retour à la carte", style: .cancel) { (_) in
            self.dismiss(animated: true, completion: nil)
        }
        
        alertController.addAction(action1)
        alertController.addAction(action2)
        if showCancelAction {
            alertController.addAction(action3)
        }
        self.present(alertController, animated: true, completion: nil)
    }
}


extension MKMapView {
    
    func showAllAnnotations() {
        self.showAnnotations(self.annotations, animated: true)
    }

    func removeAllAnnotations() {
        self.removeAnnotations(self.annotations)
    }

}
