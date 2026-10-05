import 'dart:io';

bool get browserReportsOffline => false;
bool isSocketFailure(Object error) => error is SocketException;
