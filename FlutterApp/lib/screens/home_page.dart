import 'dart:js_interop';

import 'package:algorand_dart/algorand_dart.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:walletconnect_secure_storage/walletconnect_secure_storage.dart';
import 'package:flutter/services.dart' show rootBundle;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
// Initial Selected Value
  String dropdownvalue = '';

  // List of items in our dropdown menu
  var accounts = [
    '',
  ];

  // application id
  late int _appId;
  String status = "Waiting for application to be created...";

  final algoOptions = AlgorandOptions(
    algodClient:
        AlgodClient(apiUrl: 'https://testnet-api.algonode.cloud', apiKey: ''),
    indexerClient:
        IndexerClient(apiUrl: 'https://testnet-idx.algonode.cloud', apiKey: ''),
  );

  late final Algorand algorand;

  late WalletConnect connector;
  late final AlgorandWalletConnectProvider provider;

  String _displayUri = '';
  String _account = '';

  bool _connected = false;

  void _changeDisplayUri(String uri) {
    setState(() {
      _displayUri = uri;
    });
  }

  Future createSession() async {
    // Create a new session
    if (!connector.connected) {
      final session = await connector.createSession(
        chainId: 4160, // all
        // chainId: 416002, // testnet
        onDisplayUri: (uri) => _changeDisplayUri(uri),
      );

      setState(() {
        accounts.addAll(session.accounts);
        dropdownvalue = session.accounts.first;
        if (session.accounts.first.isDefinedAndNotNull) {
          status = 'Account connected, please create an auction app';
        }
        _connected = true;
      });

      print('Connected: $session');
    }
  }

  Future initWalletConnect() async {
    algorand = Algorand(options: algoOptions);
    // Define a session storage
    final sessionStorage = WalletConnectSecureStorage();
    final session = await sessionStorage.getSession();

    // Create a connector
    connector = WalletConnect(
      bridge: 'https://bridge.walletconnect.org',
      session: session,
      sessionStorage: sessionStorage,
      clientMeta: const PeerMeta(
        name: 'Auction',
        description: 'Auction App',
        url: 'https://walletconnect.org',
        icons: [
          'https://gblobscdn.gitbook.com/spaces%2F-LJJeCjcLrr53DcT1Ml7%2Favatar.png?alt=media'
        ],
      ),
    );

    provider = AlgorandWalletConnectProvider(connector);

    setState(() {
      _account = session?.accounts.first ?? '';
      accounts.addAll(session?.accounts as Iterable<String>);
      dropdownvalue = session?.accounts.first ?? '';

      if (session!.accounts.first.isDefinedAndNotNull) {
        status = 'Account connected, please create an auction app';
      }
    });

    connector.registerListeners(
      onConnect: (status) {
        setState(() {
          _account = status.accounts[0];
        });
      },
    );
  }

  @override
  void initState() {
    initWalletConnect();
    super.initState();
  }

  void _showModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
            child: QrImageView(
          data: _displayUri,
          version: QrVersions.auto,
          size: 200.0,
        ));
      },
    );
  }

  Future<void> _showDialog() async {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Scan with Pera Wallet'),
            content: SizedBox(
              height: 200,
              width: 200,
              child: Center(
                child: QrImageView(
                  data: _displayUri,
                  version: QrVersions.auto,
                  // size: 200,
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          );
        },
      ) /*.then((value) {
        if (connector.connected) {
          //Navigator.of(context).pop(); //TODO: Hacer que se cierre automáticamente el modal cuando se cree la coenxión
        }
      })*/
          ;
    }
  }

  Future<void> createApp(Address creator) async {
    const localInts = 0;
    const localBytes = 0;
    const globalInts = 3;
    const globalBytes = 1;
    try {
      const approvalPath = 'assets/smart_contracts/auction/approval.teal';
      // var approval = await File(approvalPath).readAsString();
      var approval = await rootBundle.loadString(approvalPath);
      final approvalProgram = await algorand.compileTEAL(approval);

      const clearPath = 'assets/smart_contracts/auction/clear.teal';
      // final clear = await File(clearPath).readAsString();
      var clear = await rootBundle.loadString(clearPath);

      final clearProgram = await algorand.compileTEAL(clear);

      final params = await algorand.getSuggestedTransactionParams();

      final unsignedTx = await (ApplicationCreateTransactionBuilder()
            ..sender = creator
            ..approvalProgram = approvalProgram.program
            ..clearStateProgram = clearProgram.program
            ..globalStateSchema = StateSchema(
              numUint: globalInts,
              numByteSlice: globalBytes,
            )
            ..localStateSchema = StateSchema(
              numUint: localInts,
              numByteSlice: localBytes,
            )
            ..suggestedParams = params)
          .build();

      final signedTx = await provider.signTransaction(unsignedTx.toBytes());

      final txId = await algorand.sendRawTransactions(
        signedTx,
        waitForConfirmation: true,
      );
      final response = await algorand.waitForConfirmation(txId);
      setState(() {
        _appId = response.applicationIndex ?? 0;
      });

      if (_appId == 0) {
        throw ArgumentError();
      }
      final appAddress = Address.forApplication(_appId);
      print(
          'An application has been created with id ${_appId.toString()} App address ${appAddress.encodedAddress} TxId: $txId');
    } on AlgorandException catch (e) {
      print('Error: ${e.message}');
      rethrow;
    } catch (e) {
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: const Text('Auction algorand Demo'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.only(left: 50),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            // textBaseline: TextBaseline.alphabetic,
            children: [
              Row(
                // mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(status),
                ],
              ),
              Row(
                // mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Account:'),
                  const SizedBox(
                    width: 10,
                  ),
                  DropdownButton(
                    // Initial Value
                    value: dropdownvalue,

                    // Down Arrow Icon
                    icon: const Icon(Icons.keyboard_arrow_down),

                    // Array list of items
                    items: accounts.map((String acc) {
                      return DropdownMenuItem(
                        value: acc,
                        child: Text(acc),
                      );
                    }).toList(),
                    // After selecting the desired option,it will
                    // change button value to selected value
                    onChanged: (String? newValue) {
                      setState(() {
                        dropdownvalue = newValue!;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(
                height: 10,
              ),
              // Visibility(
              //   visible: _connected,
              //   replacement: ElevatedButton.icon(
              //     icon: const Icon(Icons.account_balance_wallet),
              //     label: const Text('Conenct'),
              //     onPressed: () async {
              //       createSession();
              //       await _showDialog();
              //       setState(() {
              //         _connected = true;
              //       });
              //     },
              //   ),
              //   child: ElevatedButton.icon(
              //     icon: const Icon(Icons.account_balance_wallet),
              //     label: const Text('Disconenct'),
              //     onPressed: () async {
              //       await connector.killSession();
              //       setState(() {
              //         _connected = false;
              //       });
              //     },
              //   ),
              // ),

              ((_displayUri.isEmpty || _displayUri.isUndefinedOrNull) ||
                      !_connected) //TODO: inicializar primero el connector o usar otra variable
                  ? ElevatedButton.icon(
                      icon: const Icon(Icons.account_balance_wallet),
                      label: const Text('Conenct'),
                      onPressed: () async {
                        createSession();
                        await _showDialog();
                        setState(() {
                          // _connected = false;
                          connector.connected;
                        });
                      },
                    )
                  : ElevatedButton.icon(
                      icon: const Icon(Icons.account_balance_wallet),
                      label: const Text('Disconenct'),
                      onPressed: () async {
                        await connector.killSession();
                        setState(() {
                          _displayUri = "";
                          connector.connected;
                        });
                      },
                    ),
              const SizedBox(
                height: 10,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.account_balance_wallet),
                label: const Text('Create app'),
                // onPressed: !_connected                    ? null                     :
                onPressed: () async {
                  await createApp(Address.fromAlgorandAddress(dropdownvalue));
                },
              ),
              const SizedBox(
                height: 10,
              ),
              Row(
                // mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('ASA ID:'),
                  const SizedBox(
                    width: 10,
                  ),
                  SizedBox(
                    width: 300,
                    child: TextField(
                        onChanged: (texto) {
                          // valor = texto;
                        },
                        decoration: const InputDecoration(
                            border: OutlineInputBorder())),
                  )
                ],
              ),
              const SizedBox(
                height: 10,
              ),
              Row(
                // mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('ASA min value (Microalgos):'),
                  const SizedBox(
                    width: 10,
                  ),
                  SizedBox(
                    width: 300,
                    child: TextField(
                        onChanged: (texto) {
                          // valor = texto;
                        },
                        decoration: const InputDecoration(
                            border: OutlineInputBorder())),
                  )
                ],
              ),
              const SizedBox(
                height: 10,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.play_circle_fill),
                label: const Text('Start Auction'),
                onPressed: !false ? null : () {},
              ),
              const SizedBox(
                height: 10,
              ),
              Row(
                // mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Bid Amount:'),
                  const SizedBox(
                    width: 10,
                  ),
                  SizedBox(
                    width: 300,
                    child: TextField(
                        onChanged: (texto) {
                          // valor = texto;
                        },
                        decoration: const InputDecoration(
                            border: OutlineInputBorder())),
                  )
                ],
              ),
              const SizedBox(
                height: 10,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.payment),
                label: const Text('Bid'),
                onPressed: !false ? null : () {},
              ),
              const SizedBox(
                height: 10,
              ),

              ElevatedButton.icon(
                icon: const Icon(Icons.payment),
                label: const Text('Claim asset'),
                onPressed: !false ? null : () {},
              ),
              Column(
                children: [
                  // Center(
                  //     child: (_displayUri.isNotEmpty && !connector.connected)
                  //         ? QrImageView(
                  //             data: _displayUri,
                  //             version: QrVersions.auto,
                  //             size: 200.0,
                  //           )
                  //         : Container()),
                  ElevatedButton(
                    child: const Text(
                      'Sign transaction',
                    ),
                    onPressed: () async {
                      final params =
                          await algorand.getSuggestedTransactionParams();

                      final address =
                          Address.fromAlgorandAddress(dropdownvalue);

                      // Build the transaction
                      final transaction = await (PaymentTransactionBuilder()
                            ..sender = address
                            ..amount = BigInt.from(500000)
                            ..receiver = address
                            ..suggestedParams = params)
                          .build();

                      // Sign the transaction
                      final signedTxs = await provider.signTransaction(
                        transaction.toBytes(),
                        params: {
                          'message': 'Payment transaction,',
                        },
                      );

                      try {
                        final txId = await algorand.sendRawTransactions(
                          signedTxs,
                          waitForConfirmation: true,
                        );
                        print(txId);
                      } catch (e) {
                        debugPrint('Error: $e');
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      // floatingActionButton: FloatingActionButton(
      //   onPressed: () async {
      //     await createSession();
      //     // _showModal(context);
      //     // _showDialog(context);
      //   },
      //   tooltip: 'Connect',
      //   child: const Icon(Icons.add),
      // ),
    );
  }

  @override
  void dispose() {
    super.dispose();
    connector.killSession();
  }
}
