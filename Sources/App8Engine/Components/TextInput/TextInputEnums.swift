//
//  TextInputEnums.swift
//  App8Engine
//
//  Shared enums for text input components (TextField, TextView)
//

import UIKit

// MARK: - Keyboard Type

extension DSL.Model.Component {

    /// Keyboard type for text input
    enum KeyboardType: String, Decodable, Sendable {
        case `default`
        case asciiCapable
        case numbersAndPunctuation
        case URL
        case numberPad
        case phonePad
        case namePhonePad
        case emailAddress
        case decimalPad
        case twitter
        case webSearch
        case asciiCapableNumberPad

        var uiKeyboardType: UIKeyboardType {
            switch self {
            case .default: return .default
            case .asciiCapable: return .asciiCapable
            case .numbersAndPunctuation: return .numbersAndPunctuation
            case .URL: return .URL
            case .numberPad: return .numberPad
            case .phonePad: return .phonePad
            case .namePhonePad: return .namePhonePad
            case .emailAddress: return .emailAddress
            case .decimalPad: return .decimalPad
            case .twitter: return .twitter
            case .webSearch: return .webSearch
            case .asciiCapableNumberPad: return .asciiCapableNumberPad
            }
        }
    }
}

// MARK: - Text Content Type (Autofill)

extension DSL.Model.Component {

    /// Text content type for iOS autofill support
    enum TextContentType: String, Decodable, Sendable {
        // Credentials
        case username
        case password
        case newPassword
        case oneTimeCode

        // Contact
        case emailAddress
        case telephoneNumber
        case name
        case givenName
        case familyName
        case middleName
        case nickname
        case namePrefix
        case nameSuffix

        // Address
        case addressCity
        case addressState
        case addressCityAndState
        case countryName
        case fullStreetAddress
        case streetAddressLine1
        case streetAddressLine2
        case postalCode
        case sublocality

        // Payment
        case creditCardNumber
        case creditCardExpiration
        case creditCardExpirationMonth
        case creditCardExpirationYear
        case creditCardSecurityCode
        case creditCardName
        case creditCardGivenName
        case creditCardMiddleName
        case creditCardFamilyName
        case creditCardType

        // Other
        case organizationName
        case jobTitle
        case URL
        case dateTime
        case birthdate
        case birthdateDay
        case birthdateMonth
        case birthdateYear
        case flightNumber
        case shipmentTrackingNumber

        var uiTextContentType: UITextContentType? {
            switch self {
            case .username: return .username
            case .password: return .password
            case .newPassword: return .newPassword
            case .oneTimeCode: return .oneTimeCode
            case .emailAddress: return .emailAddress
            case .telephoneNumber: return .telephoneNumber
            case .name: return .name
            case .givenName: return .givenName
            case .familyName: return .familyName
            case .middleName: return .middleName
            case .nickname: return .nickname
            case .namePrefix: return .namePrefix
            case .nameSuffix: return .nameSuffix
            case .addressCity: return .addressCity
            case .addressState: return .addressState
            case .addressCityAndState: return .addressCityAndState
            case .countryName: return .countryName
            case .fullStreetAddress: return .fullStreetAddress
            case .streetAddressLine1: return .streetAddressLine1
            case .streetAddressLine2: return .streetAddressLine2
            case .postalCode: return .postalCode
            case .sublocality: return .sublocality
            case .creditCardNumber: return .creditCardNumber
            case .creditCardExpiration: return .creditCardExpiration
            case .creditCardExpirationMonth: return .creditCardExpirationMonth
            case .creditCardExpirationYear: return .creditCardExpirationYear
            case .creditCardSecurityCode: return .creditCardSecurityCode
            case .creditCardName: return .creditCardName
            case .creditCardGivenName: return .creditCardGivenName
            case .creditCardMiddleName: return .creditCardMiddleName
            case .creditCardFamilyName: return .creditCardFamilyName
            case .creditCardType: return .creditCardType
            case .organizationName: return .organizationName
            case .jobTitle: return .jobTitle
            case .URL: return .URL
            case .dateTime: return .dateTime
            case .birthdate: return .birthdate
            case .birthdateDay: return .birthdateDay
            case .birthdateMonth: return .birthdateMonth
            case .birthdateYear: return .birthdateYear
            case .flightNumber: return .flightNumber
            case .shipmentTrackingNumber: return .shipmentTrackingNumber
            }
        }
    }
}

// MARK: - Return Key Type

extension DSL.Model.Component {

    /// Return key type for keyboard
    enum ReturnKeyType: String, Decodable, Sendable {
        case `default`
        case go
        case google
        case join
        case next
        case route
        case search
        case send
        case yahoo
        case done
        case emergencyCall
        case `continue`

        var uiReturnKeyType: UIReturnKeyType {
            switch self {
            case .default: return .default
            case .go: return .go
            case .google: return .google
            case .join: return .join
            case .next: return .next
            case .route: return .route
            case .search: return .search
            case .send: return .send
            case .yahoo: return .yahoo
            case .done: return .done
            case .emergencyCall: return .emergencyCall
            case .continue: return .continue
            }
        }
    }
}

// MARK: - Autocapitalization Type

extension DSL.Model.Component {

    /// Autocapitalization type
    enum AutocapitalizationType: String, Decodable, Sendable {
        case none
        case words
        case sentences
        case allCharacters

        var uiType: UITextAutocapitalizationType {
            switch self {
            case .none: return .none
            case .words: return .words
            case .sentences: return .sentences
            case .allCharacters: return .allCharacters
            }
        }
    }
}
