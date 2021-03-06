//
//  NetNode.swift
//  QueuedNet
//
//  Created by Valentin Knabel on 02.03.15.
//  Copyright (c) 2015 Valentin Knabel. All rights reserved.
//

import Foundation

/// All node raw types must implement this protocol. Nodes raw types have to be printable for better debug messages.
public protocol NetNodeRawType: CustomStringConvertible, Hashable { }

/// The possible states of nodes. Nodes can only change their state if all handlers terminated.
public enum NetNodeState: String, CustomStringConvertible {
    /// The ready state is the default state of all nodes. Only ready nodes can be run.
    case ready = "Ready"
    /// The running state. This state will automatically turn to finished if all handlers have terminated.
    case running = "Running"
    /// The finished state indicates all run-handlers have finished. Can be triggered.
    case finished = "Finished"
    /// The triggered state. Once all input nodes of a node's outgoing transition are triggered, the transition itself will be triggered.
    case triggered = "Triggered"
    /// An error state. Must be resolved by the outgoing transition.
    case error = "Error"
    
    /// A textual representation of `self`.
    public var description: String {
        return self.rawValue
    }
}

/// A net's node. Nodes can only have up to one incoming and outgoing transition.
public class NetNode<T: NetNodeRawType>: RawRepresentable, CustomStringConvertible {
    public typealias RawValue = T
    /// State handlers are always performed on referred state changes.
    /// If a state handler is blocked, it will also block the whole node for state changes.
    /// Only a state change to Error will be allowed.
    public typealias StateHandler = (NetNode<T>) -> ()
    
    /// The operation queue state handlers are performed by default.
    public var operationQueue: OperationQueue = OperationQueue()
    
    /// The state.
    private var _state: NetNodeState = .ready {
        willSet {
            assert(_queueCounter == 0, "\(self) can't set state to \(newValue).")
        }
        didSet {
            stateDidChange()
        }
    }
    /// The represented value.
    private var _rawValue: T
    /// Stores all handlers for each node state.
    private var _handlers: [NetNodeState:[(StateHandler, OperationQueue)]] = [.ready:[], .running:[], .finished:[], .error:[], .triggered: []]
    
    /// Used to determine, wether all handler's have been run.
    private var _queueCounter: Int = 0 {
        didSet {
            self.operationQueue.addOperation {
                if self._queueCounter == 0 {
                    self.operationQueue.addOperation {
                        switch self.state {
                        case .running:
                            self._state = .finished
                        case .triggered:
                            self.outgoingTransition?.run()
                        case .error:
                            self.outgoingTransition?.handleError(forNode: self)
                        default:
                            break
                        }
                    }
                }
            }
        }
    }
    
    /// The "previous" transition.
    internal var _incomingTransition: NetTransition<T>?
    /// The "next" transition.
    internal var _outgoingTransition: NetTransition<T>?
    
    /// The node's state. Defined handlers will be performed on change.
    public var state: NetNodeState {
        return _state
    }
    /// The represented raw value.
    public var rawValue: T {
        return _rawValue
    }
    /// The incoming/"previous" transition.
    public var incomingTransition: NetTransition<T>? {
        return _incomingTransition
    }
    /// The outgoing/"next" transition. Can only be run if ´self´ is in Triggered state.
    public var outgoingTransition: NetTransition<T>? {
        return _outgoingTransition
    }
    
    /// A textual representation of `self`.
    public var description: String {
        return "NetNode<\(self.state), \(self.rawValue.description)>"
    }
    
    /**
    Creates a new node instance.
    
    - Parameter rawValue The raw value to be represented.
    */
    public required init?(rawValue: T) {
        self._rawValue = rawValue
    }
    
    /**
    Guarantees a state handler to be run on internal state changes in a given queue.
    
    - Parameter state The state, the state handler should be run in.
    - Parameter perform The state handler to be performed.
    - Parameter queue The queue the state handler should be run in.
    */
    public func on(state s: NetNodeState, perform h: @escaping StateHandler, queue: OperationQueue) {
        if _handlers[s] == nil {
            self._handlers[s] = [(h, queue)]
        }
        else {
            self._handlers[s]?.append((h, queue))
        }
    }
    
    /**
    Will be invoked on state changes.
    */
    private func stateDidChange() {
        self.operationQueue.addOperation { () -> Void in
            let allops = (self._handlers[self.state]) ?? []
            for op in allops {
                self._queueCounter += 1
                op.1.addOperation {
                    op.0(self)
                    self._queueCounter -= 1
                }
            }
            if allops.count == 0 {
                self._queueCounter = 0
            }
        }
    }
    
    /// Sets the node's state from Triggered to Ready. Will be ignored otherwise.
    public func reset() {
        if self.state == .triggered {
            self._state = .ready
        }
        else {
            assertionFailure("\(self.description) can't reset. Should be NetNode<\(NetNodeState.finished), \(self.rawValue.description)>.")
        }
    }
    
    /// Sets the node's state from Ready to Running. Will automatically transition to Finished. Will be ignored otherwise.
    public func run() {
        if self.state == .ready {
            self._state = .running
        }
        else {
            assertionFailure("\(self.description) can't run. Should be NetNode<\(NetNodeState.finished), \(self.rawValue.description)>.")
        }
    }
    
    /// Sets the node's state from Finished to Triggered. Will be ignored otherwise.
    public func triggerTransition() {
        if self.state == .finished {
            self._state = .triggered
        }
        else {
            assertionFailure("\(self.description) can't trigger. Should be NetNode<\(NetNodeState.finished), \(self.rawValue.description)>.")
        }
    }
    
    /// Sets the node's state Error.
    public func error() {
        self._state = .error
    }
}

public extension NetNode {
    
    /**
    Guarantees a state handler to be run on internal state changes in the node's default operation queue.
    
    - Parameter state The state, the state handler should be run in.
    - Parameter perform The state handler to be performed.
    */
    public func on(state s: NetNodeState, perform h: @escaping StateHandler) {
        self.on(state: s, perform: h, queue: self.operationQueue)
    }
}
