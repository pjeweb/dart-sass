// Copyright 2016 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import '../ast/css/node.dart';
import '../value.dart';
import 'value.dart';

abstract class CssVisitor<T> extends ValueVisitor<T> {
  T visitComment(CssComment node) => null;
  T visitDeclaration(CssDeclaration node) => null;

  T visitStyleRule(CssStyleRule node) {
    for (var child in node.children) {
      child.accept(this);
    }
    return null;
  }

  T visitStylesheet(CssStylesheet node) {
    for (var child in node.children) {
      child.accept(this);
    }
    return null;
  }

  T visitValue(CssValue node) => node is Value ? node.accept(this) : null;
}