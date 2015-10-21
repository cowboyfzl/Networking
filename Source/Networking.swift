import Foundation
import TestCheck
import JSON

#if os(iOS)
    import UIKit
#endif

public class Networking {
    private let baseURL: String
    private var stubbedGETResponses: [String : AnyObject]
    private var stubbedPOSTResponses: [String : AnyObject]
    private static let stubsInstance = Networking(baseURL: "")

    /**
    Base initializer, it creates an instance of `Networking`.
    - parameter baseURL: The base URL for HTTP requests under `Networking`.
    */
    public init(baseURL: String) {
        self.baseURL = baseURL
        self.stubbedGETResponses = [String : AnyObject]()
        self.stubbedPOSTResponses = [String : AnyObject]()
    }

    // MARK: GET

    /**
    Makes a GET request to the specified path.
    - parameter path: The path for the GET request.
    - parameter completion: A closure that gets called when the GET request is completed, it contains a `JSON` object and an `NSError`.
    */
    public func GET(path: String, completion: (JSON: AnyObject?, error: NSError?) -> ()) {
        let request = NSURLRequest(URL: self.urlForPath(path))

        let responses = Networking.stubsInstance.stubbedGETResponses
        if let response = responses[path] {
            completion(JSON: response, error: nil)
        } else {
            #if os(iOS)
                if Test.isRunning() == false {
                    dispatch_async(dispatch_get_main_queue(), {
                        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
                    })
                }
            #endif

            let semaphore = dispatch_semaphore_create(0)
            var connectionError: NSError?
            var result: AnyObject?
            var returnedResponse: NSURLResponse?
            var returnedData: NSData?

            NSURLSession.sharedSession().dataTaskWithRequest(request, completionHandler: { data, response, error in
                returnedResponse = response
                returnedData = data

                do {
                    if let data = data {
                        result = try data.toJSON()
                    } else if let error = error {
                        connectionError = error
                    }
                } catch {
                    let userInfo : [String: AnyObject] = [
                        NSLocalizedDescriptionKey: "Converting data to JSON failed"
                    ]
                    connectionError = NSError(domain: NSCocoaErrorDomain, code: 98765, userInfo: userInfo)
                }

                if Test.isRunning() {
                    dispatch_semaphore_signal(semaphore)
                } else {
                    dispatch_async(dispatch_get_main_queue(), {
                        #if os(iOS)
                            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                        #endif

                        self.logError(data: returnedData, request: request, response: returnedResponse, error: connectionError)
                        completion(JSON: result, error: connectionError)
                    })
                }
            }).resume()

            if Test.isRunning() {
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
                self.logError(data: returnedData, request: request, response: returnedResponse, error: connectionError)
                completion(JSON: result, error: connectionError)
            }
        }
    }

    /**
    Registers a response for a GET request to the specified path. After registering this, every GET request to the path, will return
    the registered response.
    - parameter path: The path for the stubbed GET request.
    - parameter response: An `AnyObject` that will be returned when a GET request is made to the specified path.
    */
    public class func stubGET(path: String, response: AnyObject) {
        stubsInstance.stubbedGETResponses[path] = response
    }

    /**
    Registers the contents of a file as the response for a GET request to the specified path. After registering this, every GET request to the path, will return
    the contents of the registered file.
    - parameter path: The path for the stubbed GET request.
    - parameter fileName: The name of the file, whose contents will be registered as a reponse.
    - parameter bundle: The NSBundle where the file is located.
    */
    public class func stubGET(path: String, fileName: String, bundle: NSBundle = NSBundle.mainBundle()) {
        do {
            let result = try JSON.from(fileName, bundle: bundle)
            stubsInstance.stubbedGETResponses[path] = result
        } catch ParsingError.NotFound {
            fatalError("We couldn't find \(fileName), are you sure is there?")
        } catch {
            fatalError("Converting data to JSON failed")
        }
    }

    // MARK: - POST

    /**
    Makes a POST request to the specified path, using the provided parameters.
    - parameter path: The path for the GET request.
    - parameter params: The parameters to be used, they will be serialized using NSJSONSerialization.
    - parameter completion: A closure that gets called when the POST request is completed, it contains a `JSON` object and an `NSError`.
    */
    public func POST(path: String, params: AnyObject?, completion: (JSON: AnyObject?, error: NSError?) -> ()) {
        let request = NSMutableURLRequest(URL: self.urlForPath(path))
        request.HTTPMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let responses = Networking.stubsInstance.stubbedPOSTResponses
        if let response = responses[path] {
            completion(JSON: response, error: nil)
        } else {
            #if os(iOS)
                if Test.isRunning() == false {
                    dispatch_async(dispatch_get_main_queue(), {
                        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
                    })
                }
            #endif

            var serializingError: NSError?
            if let params = params {
                do {
                    request.HTTPBody = try NSJSONSerialization.dataWithJSONObject(params, options: [])
                } catch let error as NSError {
                    serializingError = error
                }
            }

            if let serializingError = serializingError {
                dispatch_async(dispatch_get_main_queue(), {
                    completion(JSON: nil, error: serializingError)
                })
            } else {
                var connectionError: NSError?
                var result: AnyObject?
                let semaphore = dispatch_semaphore_create(0)
                var returnedResponse: NSURLResponse?
                var returnedData: NSData?

                NSURLSession.sharedSession().dataTaskWithRequest(request, completionHandler: { data, response, error in
                    returnedResponse = response
                    connectionError = error
                    returnedData = data

                    if let data = data {
                        do {
                            result = try NSJSONSerialization.JSONObjectWithData(data, options: .MutableLeaves)
                        } catch let serializingError as NSError {
                            if error == nil {
                                connectionError = serializingError
                            }
                        }
                    }

                    if Test.isRunning() {
                        dispatch_semaphore_signal(semaphore)
                    } else {
                        dispatch_async(dispatch_get_main_queue(), {
                            #if os(iOS)
                                UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                            #endif

                            self.logError(params, data: returnedData, request: request, response: returnedResponse, error: connectionError)
                            completion(JSON: result, error: connectionError)
                        })
                    }
                }).resume()
                
                if Test.isRunning() {
                    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
                    self.logError(params, data: returnedData, request: request, response: returnedResponse, error: connectionError)
                    completion(JSON: result, error: connectionError)
                }
            }
        }
    }

    /**
    Registers a response for a POST request to the specified path. After registering this, every POST request to the path, will return
    the registered response.
    - parameter path: The path for the stubbed POST request.
    - parameter response: An `AnyObject` that will be returned when a POST request is made to the specified path.
    */
    public class func stubPOST(path: String, response: AnyObject) {
        stubsInstance.stubbedPOSTResponses[path] = response
    }

    /**
    Registers the contents of a file as the response for a POST request to the specified path. After registering this, every POST request to the path, will return
    the contents of the registered file.
    - parameter path: The path for the stubbed POST request.
    - parameter fileName: The name of the file, whose contents will be registered as a reponse.
    - parameter bundle: The NSBundle where the file is located.
    */
    public class func stubPOST(path: String, fileName: String, bundle: NSBundle = NSBundle.mainBundle()) {
        do {
            let result = try JSON.from(fileName, bundle: bundle)
            stubsInstance.stubbedPOSTResponses[path] = result
        } catch ParsingError.NotFound {
            fatalError("We couldn't find \(fileName), are you sure is there?")
        } catch {
            fatalError("Converting data to JSON failed")
        }
    }

    // MARK: - Utilities

    /**
    Convenience method to generated a NSURL by appending the provided path to the Networking's base URL.
    - parameter path: The path to be appended to the base URL.
    - returns: A NSURL generated after appending the path to the base URL.
    */
    public func urlForPath(path: String) -> NSURL {
        return NSURL(string: self.baseURL + path)!
    }

    // MARK: - Logging

    private func logError(params: AnyObject? = nil, data: NSData?, request: NSURLRequest?, response: NSURLResponse?, error: NSError?) {
        guard let error = error else { return }

        print(" ")
        print("========== Networking Error ==========")
        print(" ")

        print("Error \(error.code): \(error.description)")
        print(" ")

        if let request = request {
            print("Request: \(request)")
            print(" ")
        }

        if let params = params {
            print("Params: \(params)")
            print(" ")
        }

        if let data = data, stringData = NSString(data: data, encoding: NSUTF8StringEncoding) {
            print("Data: \(stringData)")
            print(" ")
        }

        if let response = response as? NSHTTPURLResponse {
            print("Response status code: \(response.statusCode)")
            print(" ")
            print("Path: \(response.URL!.absoluteString)")
            print(" ")
            print("Response: \(response)")
            print(" ")
        }

        print("================= ~ ==================")
        print(" ")
    }
}
