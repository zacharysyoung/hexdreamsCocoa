// hexdreamsCocoa
// HXStorageManager.swift
// Copyright © 2018 Kenny Leung
// This code is PUBLIC DOMAIN

import Foundation
import CoreData

public class HXResourceManager : NSObject {
    
    public enum Errors : Error {
        case capacityReached
    }
    
    public static let shared = HXResourceManager()
    
    private let serialize = DispatchQueue(label:"HXObserverCenter", qos:.default, attributes:[], autoreleaseFrequency:.workItem, target:nil)

    lazy var resourceManagerRootDirectory:URL = {
        HXApp.cachesDirectory.appendingPathComponent("HXResourceManager")
    }()
    
    lazy var metadataStoreLocation:URL = {
        self.resourceManagerRootDirectory.appendingPathComponent("Metadata").appendingPathComponent("Metadata.sqlite")
    }()
    
    lazy var storageRootDirectory:URL = {
        self.resourceManagerRootDirectory.appendingPathComponent("Storage")
    }()
    
    lazy var modelURL:URL = {
        return Bundle(for: type(of: self)).url(forResource:"HXResourceManager", withExtension: "momd") ?? {
            fatalError("Could not find HXResourceManager model")
        }
    }()
    
    lazy var persistentContainer:NSPersistentContainer = {
        let model = NSManagedObjectModel(contentsOf:self.modelURL) ?? {
            fatalError("Could not load model at \(self.modelURL)")
        }
        let storeDescription = NSPersistentStoreDescription(url:self.metadataStoreLocation)
        let persistentContainer = NSPersistentContainer(name:"HXResourceManager", managedObjectModel:model)
        persistentContainer.persistentStoreDescriptions = [storeDescription]
        return persistentContainer
    }()

    var viewContext:NSManagedObjectContext {
        return self.persistentContainer.viewContext
    }
    
    lazy var moc:NSManagedObjectContext = {
        self.persistentContainer.newBackgroundContext()
    }()
    
    var domainsByIdentifier:[String:HXStorageDomain]
    
    private func cacheDomains() {
        do {
            try self.viewContext.hxPerformAndWait {
                let domains = $0.hxFetch(entity:HXStorageDomain.self, predicate:nil, sortString:nil, returnFaults:false)
                try self.domainsByIdentifier = domains.mapDict({$0.identifier})
            }
        } catch {
            fatalError("Could not cache domains")
        }
    }

    public func domainFor(identifier:String) throws -> HXStorageDomain {
         return try self.domainsByIdentifier[identifier] ?? {
            throw hxthrown(.invalidArgument("No domain with identifier \(identifier)"))
        }
    }
    
    private func generateResourceURL(domain:HXStorageDomain, uuid:UUID, filename:String) -> URL {
        var path = self.storageRootDirectory
        for d in domain.path {
            path.appendPathComponent(d.name ?? "_")
        }
        path.appendPathComponent("\(uuid.uuidString)-\(filename)")
        return path
    }
            
    override init() {
        self.domainsByIdentifier = [String:HXStorageDomain]()
        super.init()
        self.cacheDomains()
    }
    
    public func resourceFor(
        domainIdentifier:String,
        uuid:UUID?,
        url:URL?,
        version:String?,
        completionHandler:@escaping (String?, [HXResource]?, Error?) -> Void
        )
    {
        self.serialize.hxAsync({
            let privateResults:[HXResource] = try self.moc.hxPerformAndWait {
                let domain = try $0.hxTranslate(foreignObject:self.domainFor(identifier:domainIdentifier))
                return try self.fetchResourcesFor(domain:domain, uuid:uuid, url:url, version:version, moc:$0)
            }
            
            DispatchQueue.main.hxAsync({
                let results = try self.viewContext.hxTranslate(foreignObjects:privateResults)
                switch results.count {
                case 0:
                    completionHandler(nil, nil, nil)
                case 1:
                    completionHandler(results[0].path, results, nil)
                default:
                    completionHandler(nil, results, self.hxthrown(.invalidArgument("More than one resource found for domain:\(domainIdentifier), uuid:\(String(describing:uuid)), url:\(url?.absoluteString ?? "nil"), version:\(version ?? "nil")")))
                }
            }, hxCatch: {
                self.hxcaught($0)
                completionHandler(nil, nil, $0)
            })
            
        }, hxCatch: {
            self.hxcaught($0)
            completionHandler(nil, nil, $0)
        })
    }
    
    public func register(
        resource downloadedURL:URL,
        forDomainIdentifier domainIdentifier:String,
        uuid:UUID?,
        url:URL?,
        version:String?,
        purgePriority:Int16,
        completionHandler:@escaping (HXResource?, Error?) -> Void
        )
    {
        self.serialize.hxAsync({
            let registeredResource:HXResource = try self.moc.hxPerformAndWait {
                let now = Date()
                let domain = try $0.hxTranslate(foreignObject:self.domainFor(identifier:domainIdentifier))
                let results = try self.fetchResourcesFor(domain:domain, uuid:uuid, url:url, version:version, moc:$0)
                if results.count > 1 {
                    let message = "More than one resource found for domain:\(domainIdentifier), uuid:\(String(describing:uuid)), url:\(url?.absoluteString ?? "nil"), version:\(version ?? "nil")"
                    throw self.hxthrown(.moreThanOneObjectFound(message, results))
                }
                let existingResource = results.last
                let oldSize = existingResource?.size
                let newSize = try FileManager.default.attributesOfItem(atPath:downloadedURL.path)[.size] as? Int64 ?? {throw self.hxthrown(.cocoa("Could not get size of downloaded file at \(downloadedURL)", nil))}
                let delta = newSize - (oldSize ?? 0)
                
                if try self.makeRoomFor(bytes:delta, moc:$0) == false {
                    throw HXResourceManager.Errors.capacityReached
                }
                
                let resource = existingResource ?? HXResource(context:$0)
                if resource.isInserted {
                    let uuid = uuid ?? UUID()
                    resource.createDate = now
                    resource.accessDate = now
                    if let url = url {
                        resource.sourceURLString = url.absoluteString
                        resource.path = self.generateResourceURL(domain:domain, uuid:uuid, filename:HXSafeFilename(url.lastPathComponent, fixLength:10)).path
                    } else {
                        resource.path = self.generateResourceURL(domain:domain, uuid:uuid, filename:"noname").path
                    }
                    resource.purgePriority = purgePriority
                    resource.uuid = uuid
                    resource.version = version
                    resource.domain = domain
                }
                resource.purgeDate = nil
                resource.updateDate = now
                domain.adjustSize(delta:delta)
                
                let destPath = try resource.path ?? {throw self.hxthrown(.hxnil("resource.path"))}
                try FileManager.default.moveItem(at:downloadedURL, to:URL(fileURLWithPath:destPath))
                
                try $0.save()
                return resource
            }
            
            DispatchQueue.main.hxAsync({
                let mainResource = try self.moc.hxTranslate(foreignObject:registeredResource)
                completionHandler(mainResource, nil)
            }, hxCatch: {
                self.hxcaught($0)
                completionHandler(nil, $0)
            })
            
        }, hxCatch: {
            self.hxcaught($0)
            completionHandler(nil, $0)
        })
    }
    
    // Higher valued purge priorities go first. 0 means never purge
    // return true means success, false means no more space
    public func makeRoomFor(bytes:Int64, moc:NSManagedObjectContext) throws -> Bool {
        fatalError("Not Implemented")
    }
    
    private func fetchResourcesFor(
        domain:HXStorageDomain,
        uuid:UUID?,
        url:URL?,
        version:String?,
        moc:NSManagedObjectContext
        ) throws
        -> [HXResource]
    {
        var predicates = [NSPredicate]()
        
        predicates.append(NSPredicate(format:"domain = %@", argumentArray:[domain]))
        if let uuid = uuid {
            predicates.append(NSPredicate(format:"uuid = %@", argumentArray:[uuid]))
        }
        if let urlString = url?.absoluteString {
            predicates.append(NSPredicate(format:"urlString = %@", argumentArray:[urlString]))
        }
        if let version = version {
            predicates.append(NSPredicate(format:"version = %@", argumentArray:[version]))
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates:predicates)
        return moc.hxFetch(entity:HXResource.self, predicate:predicate, sortString:nil, returnFaults:false)
    }

}
