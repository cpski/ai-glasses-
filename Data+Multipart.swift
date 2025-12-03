//
//  Data+Multipart.swift
//  GlassesTestAssistant
//
//  Created by Connor Pauley on 12/1/25.
//


import Foundation

/// Helpers to build a multipart/form-data body.
extension Data {

    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }

    mutating func appendMultipartBoundary(_ boundary: String) {
        appendString("--\(boundary)\r\n")
    }

    mutating func appendMultipartFileField(name: String,
                                           filename: String,
                                           mimeType: String,
                                           fileData: Data) {
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(fileData)
        appendString("\r\n")
    }

    mutating func appendMultipartClosingBoundary(_ boundary: String) {
        appendString("--\(boundary)--\r\n")
    }
}
