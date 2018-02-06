//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

/// A `FileHandle` is a handle to an open file.
///
/// When creating a `FileHandle` it takes ownership of the underlying file descriptor. When a `FileHandle` is no longer
/// needed you must `close` it or take back ownership of the file descriptor using `takeDescriptorOwnership`.
///
/// - note: One underlying file descriptor should usually be managed by one `FileHandle` only.
///
/// - warning: Failing to manage the lifetime of a `FileHandle` correctly will result in undefined behaviour.
///
/// - warning: `FileHandle` objects are not thread-safe and are mutable. They also cannot be fully thread-safe as they refer to a global underlying file descriptor.
public final class FileHandle {
    private var open: Bool
    private let descriptor: CInt

    /// Create a `FileHandle` taking ownership of `descriptor`. You must call `FileHandle.close` or `FileHandle.takeDescriptorOwnership` before
    /// this object can be safely released.
    public init(descriptor: CInt) {
        self.descriptor = descriptor
        self.open = true
    }

    deinit {
        assert(!self.open, "leaked open FileHandle(descriptor: \(self.descriptor)). Call `close()` to close or `takeDescriptorOwnership()` to take ownership and close by some other means.")
    }

    /// Duplicates this `FileHandle`. This means that a new `FileHandle` object with a new underlying file descriptor
    /// is returned. The caller takes ownership of the returned `FileHandle` and is responsible for closing it.
    ///
    /// - warning: The returned `FileHandle` is not fully independent, the seek pointer is shared as documented by `dup(2)`.
    ///
    /// - returns: A new `FileHandle` with a fresh underlying file descriptor but shared seek pointer.
    public func duplicate() throws -> FileHandle {
        guard self.open else {
            throw IOError(errnoCode: EBADF, reason: "can't close file (as it's not open anymore).")
        }

        return FileHandle(descriptor: try Posix.dup(descriptor: self.descriptor))
    }

    /// Take the ownership of the underlying file descriptor. This is similar to `close()` but the underlying file
    /// descriptor remains open. The caller is responsible for closing the file descriptor by some other means.
    ///
    /// After calling this, the `FileHandle` cannot be used for anything else and all the operations will throw.
    ///
    /// - returns: The underlying file descriptor, now owned by the caller.
    public func takeDescriptorOwnership() throws -> CInt {
        guard self.open else {
            throw IOError(errnoCode: EBADF, reason: "can't close file (as it's not open anymore).")
        }

        defer {
            self.open = false
        }
        return self.descriptor
    }

    /// Closes this `FileHandle` which will also close the underlying file descriptor.
    ///
    /// After calling this, the `FileHandle` cannot be used for anything else and all the operations will throw.
    public func close() throws {
        guard self.open else {
            throw IOError(errnoCode: EBADF, reason: "can't close file (as it's not open anymore).")
        }

        try Posix.close(descriptor: self.descriptor)
        self.open = false
    }

    /// Temporarily take ownership of the underlying file descriptor. When the closure returns, the ownership of the
    /// file descriptor is returned into the `FileHandle`.
    ///
    /// - warning: Do not escape the file descriptor passed to the closure.
    ///
    /// - parameters:
    ///    - body: A closure which temporarily gets access to the underlying file descriptor.
    /// - returns: The value returned by the `body` closure.
    public func withDescriptor<T>(_ body: (CInt) throws -> T) throws -> T {
        guard self.open else {
            throw IOError(errnoCode: EBADF, reason: "can't close file (as it's not open anymore).")
        }
        return try body(self.descriptor)
    }
}

extension FileHandle {
    /// Open a new `FileHandle`.
    ///
    /// - parameters:
    ///     - path: the path of the file to open. The ownership of the file descriptor is transferred to this `FileHandle` and so it will be closed once `close` is called.
    public convenience init(path: String) throws {
        let fd = try Posix.open(file: path, oFlag: O_RDONLY | O_CLOEXEC)
        self.init(descriptor: fd)
    }

}
