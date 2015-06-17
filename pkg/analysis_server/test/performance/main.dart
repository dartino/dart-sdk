// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library server.performance;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart';

import 'driver.dart';
import 'input_converter.dart';
import 'operation.dart';

/**
 * The amount of time to give the server to respond to a shutdown request
 * before forcibly terminating it.
 */
const Duration SHUTDOWN_TIMEOUT = const Duration(seconds: 25);

/**
 * Launch and interact with the analysis server.
 */
main(List<String> rawArgs) {
  Logger logger = new Logger('Performance Measurement Client');
  logger.onRecord.listen((LogRecord rec) {
    print(rec.message);
  });
  ArgResults args = parseArgs(rawArgs);

  Driver driver = new Driver(logger);
  Stream<Operation> stream = openInput(args);
  StreamSubscription<Operation> subscription;
  subscription = stream.listen((Operation op) {
    Future future = driver.perform(op);
    if (future != null) {
      logger.log(Level.FINE, 'pausing operations for ${op.runtimeType}');
      subscription.pause(future.then((_) {
        logger.log(Level.FINE, 'resuming operations');
      }));
    }
  }, onDone: () {
    subscription.cancel();
    driver.stopServer(SHUTDOWN_TIMEOUT);
  }, onError: (e, s) {
    subscription.cancel();
    logger.log(Level.SEVERE, '$e\n$s');
    driver.stopServer(SHUTDOWN_TIMEOUT);
  });
  driver.runComplete.then((Results results) {
    results.printResults();
  }).whenComplete(() {
    return subscription.cancel();
  });
}

const HELP_CMDLINE_OPTION = 'help';
const INPUT_CMDLINE_OPTION = 'input';
const MAP_FROM_OPTION = 'mapFrom';
const MAP_TO_OPTION = 'mapTo';
const VERBOSE_CMDLINE_OPTION = 'verbose';
const VERY_VERBOSE_CMDLINE_OPTION = 'vv';

/**
 * Open and return the input stream specifying how this client
 * should interact with the analysis server.
 */
Stream<Operation> openInput(ArgResults args) {
  Stream<List<int>> inputRaw;
  String inputPath = args[INPUT_CMDLINE_OPTION];
  if (inputPath == null) {
    return null;
  }
  if (inputPath == 'stdin') {
    inputRaw = stdin;
  } else {
    inputRaw = new File(inputPath).openRead();
  }
  Map<String, String> srcPathMap = new Map<String, String>();
  String mapFrom = args[MAP_FROM_OPTION];
  if (mapFrom != null && mapFrom.isNotEmpty) {
    String mapTo = args[MAP_TO_OPTION];
    srcPathMap[mapFrom] = mapTo;
    new Logger('openInput').log(
        Level.INFO, 'mapping source paths\n  from $mapFrom\n  to   $mapTo');
  }
  return inputRaw
      .transform(SYSTEM_ENCODING.decoder)
      .transform(new LineSplitter())
      .transform(new InputConverter(srcPathMap));
}

/**
 * Parse the command line arguments.
 */
ArgResults parseArgs(List<String> rawArgs) {
  ArgParser parser = new ArgParser();

  parser.addOption(INPUT_CMDLINE_OPTION,
      abbr: 'i',
      help: 'The input file specifying how this client should interact '
      'with the server. If the input file name is "stdin", '
      'then the instructions are read from standard input.');
  parser.addOption(MAP_FROM_OPTION,
      help: 'The original source directory when the instrumentation '
      'or log file was generated.');
  parser.addOption(MAP_TO_OPTION,
      help: 'The target source directory used during performance testing. '
      'WARNING: The contents of this directory will be modified');
  parser.addFlag(VERBOSE_CMDLINE_OPTION,
      abbr: 'v', help: 'Verbose logging', negatable: false);
  parser.addFlag(VERY_VERBOSE_CMDLINE_OPTION,
      help: 'Extra verbose logging', negatable: false);
  parser.addFlag(HELP_CMDLINE_OPTION,
      abbr: 'h', help: 'Print this help information', negatable: false);

  ArgResults args;
  try {
    args = parser.parse(rawArgs);
  } on Exception catch (e) {
    print(e);
    printHelp(parser);
    exit(1);
  }

  bool showHelp = args[HELP_CMDLINE_OPTION] || args.rest.isNotEmpty;

  bool isMissing(key) => args[key] == null || args[key].isEmpty;

  if (isMissing(INPUT_CMDLINE_OPTION)) {
    print('missing "input" argument');
    showHelp = true;
  }

  if (isMissing(MAP_FROM_OPTION) != isMissing(MAP_TO_OPTION)) {
    print('must specifiy both $MAP_FROM_OPTION and $MAP_TO_OPTION');
    showHelp = true;
  }

  if (args[VERY_VERBOSE_CMDLINE_OPTION] || rawArgs.contains('-vv')) {
    Logger.root.level = Level.FINE;
  } else if (args[VERBOSE_CMDLINE_OPTION]) {
    Logger.root.level = Level.INFO;
  } else {
    Logger.root.level = Level.WARNING;
  }

  if (showHelp) {
    printHelp(parser);
    exit(1);
  }

  return args;
}

void printHelp(ArgParser parser) {
  print('');
  print('Launch and interact with the AnalysisServer');
  print(parser.usage);
}
