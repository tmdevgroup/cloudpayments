import 'dart:io';

import 'package:cloudpayments/cloudpayments.dart';
import 'package:equatable/equatable.dart';
import 'package:example/main.dart';
import 'package:example/network/api/cloudpayments_api.dart';
import 'package:example/network/ip_service.dart';
import 'package:example/screens/checkout/bloc/checkout_constants.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'checkout_state.dart';
part 'checkout_event.dart';

class CheckoutBloc extends Bloc<CheckoutEvent, CheckoutState> {
  CheckoutBloc()
      : super(const CheckoutState(
          isLoading: false,
          isGooglePayAvailable: false,
        ));

  final _ipService = IpService();
  final _googlePay = CloudpaymentsGooglePay(GooglePayEnvironment.test);
  final _applePay = CloudpaymentsApplePay();
  final _cloudPaymentApi = CloudPaymentsAPI(
    secret: CheckoutConstants.secret,
    clientId: CheckoutConstants.clientId,
  );

  @override
  Stream<CheckoutState> mapEventToState(CheckoutEvent event) async* {
    if (event is Init) {
      yield* _init(event);
    } else if (event is PayButtonPressed) {
      yield* _onPayButtonPressed(event);
    } else if (event is Auth) {
      yield* _auth(event);
    } else if (event is Show3DS) {
      yield* _show3DS(event);
    } else if (event is Post3DS) {
      yield* _post3DS(event);
    } else if (event is GooglePayPressed) {
      yield* _googlePayPressed(event);
    } else if (event is ApplePayPressed) {
      yield* _applePayPressed(event);
    } else if (event is Charge) {
      yield* _charge(event);
    }
  }

  Stream<CheckoutState> _init(Init event) async* {
    if (Platform.isAndroid) {
      final isGooglePayAvailable = await _googlePay.isGooglePayAvailable();
      yield state.copyWith(
          isGooglePayAvailable: isGooglePayAvailable,
          isApplePayAvailable: false);
    } else if (Platform.isIOS) {
      final isApplePayAvailable = await _applePay.isApplePayAvailable();
      yield state.copyWith(
          isApplePayAvailable: isApplePayAvailable,
          isGooglePayAvailable: false);
    }
    yield state;
  }

  Stream<CheckoutState> _onPayButtonPressed(PayButtonPressed event) async* {
    final cardNumber = event.cardNumber;
    final expiryDate = event.expiryDate;
    final cvcCode = event.cvcCode;

    if (cardNumber == null || expiryDate == null || cvcCode == null) {
      yield state.copyWith(cardHolderError: 'Somthing fields is empty');
      return;
    }

    final isCardHolderValid = event.cardHolder?.isNotEmpty ?? false;
    final isValidCardNumber = await Cloudpayments.isValidNumber(cardNumber);
    final isValidExpiryDate = await Cloudpayments.isValidExpiryDate(expiryDate);
    final isValidCvcCode = cvcCode.length == 3;

    if (!isCardHolderValid) {
      yield state.copyWith(cardHolderError: 'Card holder can\'t be blank');
      return;
    } else if (!isValidCardNumber) {
      yield state.copyWith(cardNumberError: 'Invalid card number');
      return;
    } else if (!isValidExpiryDate) {
      yield state.copyWith(expiryDateError: 'Date invalid or expired');
      return;
    } else if (!isValidCvcCode) {
      yield state.copyWith(cvcError: 'Incorrect cvv code');
      return;
    }

    yield state.copyWith(
      cardHolderError: null,
      cardNumberError: null,
      expiryDateError: null,
      cvcError: null,
    );

    try {
      final cryptogram = await Cloudpayments.cardCryptogram(
        cardNumber: event.cardNumber!,
        cardDate: event.expiryDate!,
        cardCVC: event.cvcCode!,
        publicId: CheckoutConstants.clientId,
      );

      if (cryptogram.cryptogram != null) {
        add(Auth(cryptogram.cryptogram!, event.cardHolder!, 1));
      }
    } catch (e, st) {
      talker.handle(e, st);
    }
  }

  Stream<CheckoutState> _googlePayPressed(GooglePayPressed event) async* {
    final prevState = state;
    yield state.copyWith(isLoading: true);

    try {
      final result = await _googlePay.requestGooglePayPayment(
        price: '2.34',
        currencyCode: 'RUB',
        countryCode: 'RU',
        merchantName: CheckoutConstants.merchantName,
        publicId: CheckoutConstants.clientId,
      );

      yield state.copyWith(isLoading: false);

      if (result.isSuccess) {
        final token = result.token;
        if (token == null) {
          throw Exception('Response token is null');
        }
        add(Charge(token, 'Google Pay', 220));
        return;
      }
      if (result.isError) {
        yield CheckoutError(result.errorDescription ?? 'error');
      } else if (result.isCanceled) {
        yield const CheckoutError('Google pay has canceled');
      }
      yield prevState;
    } catch (e, st) {
      talker.handle(e, st);
      yield CheckoutError('$e');
      yield prevState;
    }
  }

  Stream<CheckoutState> _applePayPressed(ApplePayPressed event) async* {
    final prevState = state;
    yield state.copyWith(isLoading: true);

    try {
      final result = await _applePay.requestApplePayPayment(
        merchantId: 'merchant.com.YOURDOMAIN',
        currencyCode: 'RUB',
        countryCode: 'RU',
        products: [
          {"name": "Манго", "price": "650.50"}
        ],
      );

      if (result.isSuccess) {
        final token = result.token;
        if (token == null) {
          throw Exception('Response token is null');
        }
        add(Auth(token, '', 650.50));
        return;
      }
      if (result.isError) {
        yield CheckoutError(result.errorMessage ?? 'error');
      } else if (result.isCanceled) {
        yield const CheckoutError('Apple pay has canceled');
      }
      yield prevState;
    } catch (e, st) {
      talker.handle(e, st);
      yield CheckoutError('$e');
      yield prevState;
    }
  }

  Stream<CheckoutState> _charge(Charge event) async* {
    final prevState = state;
    yield state.copyWith(isLoading: true);

    try {
      final ip = await _ipService.getIp();
      final request = PayRequest(
        amount: event.amount,
        currency: "RUB",
        name: event.cardHolder,
        cardCryptogramPacket: event.token,
        invoiceId: "1122",
        description: "Оплата товаров",
        accountId: "123",
        ipAddress: ip,
      );
      final transaction = await _cloudPaymentApi.charge(request);
      yield CheckoutError(transaction.message ?? 'error');
      yield prevState;
    } catch (e, st) {
      talker.handle(e, st);
      yield CheckoutError('$e');
      yield prevState;
    }
  }

  Stream<CheckoutState> _auth(Auth event) async* {
    final prevState = state;
    yield state.copyWith(isLoading: true);

    try {
      final ip = await _ipService.getIp();
      final transaction = await _cloudPaymentApi.auth(
        PayRequest(
          amount: event.amount,
          name: event.cardHolder,
          cardCryptogramPacket: event.cryptogram,
          ipAddress: ip,
          currency: "RUB",
          invoiceId: "1122",
          description: "Оплата товаров",
          accountId: "123",
        ),
      );

      yield state.copyWith(isLoading: false);
      if (transaction.model?.paReq != null &&
          transaction.model?.acsUrl != null) {
        add(Show3DS(transaction));
        return;
      }
      yield CheckoutError(transaction.model?.cardHolderMessage ?? 'error');
      yield prevState;
    } catch (e, st) {
      talker.handle(e, st);
      yield CheckoutError('$e');
      yield prevState;
    }
  }

  Stream<CheckoutState> _show3DS(Show3DS event) async* {
    final prevState = state;
    try {
      final transaction = event.transaction;
      final result = await Cloudpayments.show3ds(
        acsUrl: transaction.model!.acsUrl!,
        transactionId: transaction.model!.transactionId!.toString(),
        paReq: transaction.model!.paReq!,
      );

      if (result != null) {
        if (result.success ?? false) {
          add(Post3DS(result.md!, result.paRes!));
          return;
        }
        yield CheckoutError(result.error ?? 'error');
      }
      yield prevState;
    } catch (e, st) {
      talker.handle(e, st);
      yield CheckoutError('$e');
      yield prevState;
    }
  }

  Stream<CheckoutState> _post3DS(Post3DS event) async* {
    final prevState = state;
    yield state.copyWith(isLoading: true);

    try {
      final transaction = await _cloudPaymentApi.post3ds(
        Post3dsRequest(event.id, event.paRes),
      );
      yield CheckoutError(transaction.model?.cardHolderMessage ?? 'error');
    } catch (e, st) {
      talker.handle(e, st);
      yield state.copyWith(isLoading: false);
      yield CheckoutError('$e');
      yield prevState;
    }
  }
}
