//
//  Util.swift
//  Frimousse
//
//  Created by Thibaut NOAH on 04/12/2017.
//  Copyright © 2017 mvpstars. All rights reserved.
//

import Foundation
import UIKit

class Util {
    
    // MARK: – Variables
    static let documentsDir = Util.getDocumentsDirectory()
    
    // MARK: – Methods
    static func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0].appendingPathComponent("Pictures", isDirectory: true)
        var objcBool:ObjCBool = true
        let exist = FileManager.default.fileExists(atPath: documentsDirectory.path, isDirectory: &objcBool)
        if !exist {
            do {
                try FileManager.default.createDirectory(atPath: documentsDirectory.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Something went wrong while creating a new folder")
            }
        }
        return documentsDirectory
    }
    
    static func deleteImageFrom(path: String) throws {
        let imagePath = Util.documentsDir.appendingPathComponent(path).path
        if FileManager.default.fileExists(atPath: imagePath) {
            try FileManager.default.removeItem(atPath: imagePath)
        }
    }
    
    // MARK: – UIImage methods
    
    static func fixOrientation(_ originalImage: UIImage) -> UIImage {
        if originalImage.imageOrientation == UIImageOrientation.up {
            return originalImage
        }
        var transform = CGAffineTransform.identity
        
        switch originalImage.imageOrientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: originalImage.size.width, y: originalImage.size.height)
            transform = transform.rotated(by: CGFloat.pi);
            
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: originalImage.size.width, y: 0);
            transform = transform.rotated(by: CGFloat.pi);
            
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: originalImage.size.height);
            transform = transform.rotated(by: -CGFloat.pi);
            
        case .up, .upMirrored:
            break
        }
        switch originalImage.imageOrientation {
            
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: originalImage.size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
            
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: originalImage.size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1);
            
        default:
            break;
        }
        
        // Now we draw the underlying CGImage into a new context, applying the transform
        // calculated above.
        let ctx = CGContext(
            data: nil,
            width: Int(originalImage.size.width),
            height: Int(originalImage.size.height),
            bitsPerComponent: originalImage.cgImage!.bitsPerComponent,
            bytesPerRow: 0,
            space: originalImage.cgImage!.colorSpace!,
            bitmapInfo: UInt32(originalImage.cgImage!.bitmapInfo.rawValue)
        )
        
        ctx!.concatenate(transform);
        
        switch originalImage.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            // Grr...
            ctx!.draw(originalImage.cgImage!, in: CGRect(x: 0, y: 0, width: originalImage.size.height,height: originalImage.size.width));
            
        default:
            ctx!.draw(originalImage.cgImage!, in: CGRect(x: 0, y: 0, width: originalImage.size.width,height: originalImage.size.height));
            break;
        }
        
        // And now we just create a new UIImage from the drawing context
        let cgimg = ctx!.makeImage()
        
        let img = UIImage(cgImage: cgimg!)
        
        return img
    }
    
    // resize an image to fit in screen width
    static func getResizedImageToFitScreenHeight(_ image: UIImage, frameHeight: CGFloat, hasAlpha: Bool = false) -> UIImage? {
        
        let rotatedImage = fixOrientation(image)
        let imageWidth = rotatedImage.size.height
        let ratio = frameHeight / imageWidth
        
        let size = image.size.applying(CGAffineTransform(scaleX: CGFloat(ratio), y: CGFloat(ratio)))
        let scale: CGFloat = 0.0 // Automatically use scale factor of main screen
        
        UIGraphicsBeginImageContextWithOptions(size, !hasAlpha, scale)
        image.draw(in: CGRect(origin: CGPoint.zero, size: size))
        
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return scaledImage
    }
}
