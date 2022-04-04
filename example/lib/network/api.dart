import 'package:cloudpayments/cloudpayments.dart';
import 'package:example/network/network.dart';
import 'package:cloudpayments/api/models/post_3ds_request.dart';
import 'package:example/network/urls.dart';

class Api {
  final _network = Network(Constants.apiUrl);

  Future<Transaction> auth(
    String cardCryptogramPacket,
    String cardHolderName,
    String amount,
  ) async {
    final request = PayRequest(
      amount: amount,
      currency: "RUB",
      name: cardHolderName,
      cardCryptogramPacket: cardCryptogramPacket,
      invoiceId: "1122",
      description: "Оплата товаров",
      accountId: "123",
      jsonData: {
        "age": 27,
        "name": "Ivan",
        "phone": "+79998881122",
      },
    );

    final response = await _network.post(
      Constants.authUrl,
      headers: {'Content-Type': 'application/json'},
      body: request.toJson(),
    );

    return Transaction.fromJson(response.data);
  }

  Future<Transaction> charge(
      String cardCryptogramPacket, String cardHolderName, String amount) async {
    final request = PayRequest(
      amount: amount,
      currency: "RUB",
      name: cardHolderName,
      cardCryptogramPacket: cardCryptogramPacket,
      invoiceId: "1122",
      description: "Оплата товаров",
      accountId: "123",
      jsonData: {
        "age": 27,
        "name": "Ivan",
        "phone": "+79998881122",
      },
    );

    final response = await _network.post(
      Constants.chargeUrl,
      headers: {'Content-Type': 'application/json'},
      body: request.toJson(),
    );

    return Transaction.fromJson(response.data);
  }

  Future<Transaction> post3ds(String transactionId, String paRes) async {
    final request = Post3dsRequest(transactionId, paRes);

    final response = await _network.post(
      Constants.post3ds,
      headers: {'Content-Type': 'application/json'},
      body: request.toJson(),
    );

    return Transaction.fromJson(response.data);
  }
}
