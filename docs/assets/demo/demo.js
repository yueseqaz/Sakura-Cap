var du = { exports: {} }, vl = {}, pu = { exports: {} }, se = {};
/**
 * @license React
 * react.production.min.js
 *
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
var Ka;
function ld() {
  if (Ka) return se;
  Ka = 1;
  var d = Symbol.for("react.element"), w = Symbol.for("react.portal"), f = Symbol.for("react.fragment"), N = Symbol.for("react.strict_mode"), j = Symbol.for("react.profiler"), C = Symbol.for("react.provider"), V = Symbol.for("react.context"), ee = Symbol.for("react.forward_ref"), I = Symbol.for("react.suspense"), ce = Symbol.for("react.memo"), O = Symbol.for("react.lazy"), ie = Symbol.iterator;
  function re(u) {
    return u === null || typeof u != "object" ? null : (u = ie && u[ie] || u["@@iterator"], typeof u == "function" ? u : null);
  }
  var oe = { isMounted: function() {
    return !1;
  }, enqueueForceUpdate: function() {
  }, enqueueReplaceState: function() {
  }, enqueueSetState: function() {
  } }, Z = Object.assign, te = {};
  function q(u, c, m) {
    this.props = u, this.context = c, this.refs = te, this.updater = m || oe;
  }
  q.prototype.isReactComponent = {}, q.prototype.setState = function(u, c) {
    if (typeof u != "object" && typeof u != "function" && u != null) throw Error("setState(...): takes an object of state variables to update or a function which returns an object of state variables.");
    this.updater.enqueueSetState(this, u, c, "setState");
  }, q.prototype.forceUpdate = function(u) {
    this.updater.enqueueForceUpdate(this, u, "forceUpdate");
  };
  function we() {
  }
  we.prototype = q.prototype;
  function Ne(u, c, m) {
    this.props = u, this.context = c, this.refs = te, this.updater = m || oe;
  }
  var Me = Ne.prototype = new we();
  Me.constructor = Ne, Z(Me, q.prototype), Me.isPureReactComponent = !0;
  var ve = Array.isArray, Oe = Object.prototype.hasOwnProperty, Ie = { current: null }, je = { key: !0, ref: !0, __self: !0, __source: !0 };
  function D(u, c, m) {
    var x, k = {}, T = null, H = null;
    if (c != null) for (x in c.ref !== void 0 && (H = c.ref), c.key !== void 0 && (T = "" + c.key), c) Oe.call(c, x) && !je.hasOwnProperty(x) && (k[x] = c[x]);
    var Y = arguments.length - 2;
    if (Y === 1) k.children = m;
    else if (1 < Y) {
      for (var Q = Array(Y), K = 0; K < Y; K++) Q[K] = arguments[K + 2];
      k.children = Q;
    }
    if (u && u.defaultProps) for (x in Y = u.defaultProps, Y) k[x] === void 0 && (k[x] = Y[x]);
    return { $$typeof: d, type: u, key: T, ref: H, props: k, _owner: Ie.current };
  }
  function Et(u, c) {
    return { $$typeof: d, type: u.type, key: c, ref: u.ref, props: u.props, _owner: u._owner };
  }
  function De(u) {
    return typeof u == "object" && u !== null && u.$$typeof === d;
  }
  function xe(u) {
    var c = { "=": "=0", ":": "=2" };
    return "$" + u.replace(/[=:]/g, function(m) {
      return c[m];
    });
  }
  var be = /\/+/g;
  function Be(u, c) {
    return typeof u == "object" && u !== null && u.key != null ? xe("" + u.key) : c.toString(36);
  }
  function Ye(u, c, m, x, k) {
    var T = typeof u;
    (T === "undefined" || T === "boolean") && (u = null);
    var H = !1;
    if (u === null) H = !0;
    else switch (T) {
      case "string":
      case "number":
        H = !0;
        break;
      case "object":
        switch (u.$$typeof) {
          case d:
          case w:
            H = !0;
        }
    }
    if (H) return H = u, k = k(H), u = x === "" ? "." + Be(H, 0) : x, ve(k) ? (m = "", u != null && (m = u.replace(be, "$&/") + "/"), Ye(k, c, m, "", function(K) {
      return K;
    })) : k != null && (De(k) && (k = Et(k, m + (!k.key || H && H.key === k.key ? "" : ("" + k.key).replace(be, "$&/") + "/") + u)), c.push(k)), 1;
    if (H = 0, x = x === "" ? "." : x + ":", ve(u)) for (var Y = 0; Y < u.length; Y++) {
      T = u[Y];
      var Q = x + Be(T, Y);
      H += Ye(T, c, m, Q, k);
    }
    else if (Q = re(u), typeof Q == "function") for (u = Q.call(u), Y = 0; !(T = u.next()).done; ) T = T.value, Q = x + Be(T, Y++), H += Ye(T, c, m, Q, k);
    else if (T === "object") throw c = String(u), Error("Objects are not valid as a React child (found: " + (c === "[object Object]" ? "object with keys {" + Object.keys(u).join(", ") + "}" : c) + "). If you meant to render a collection of children, use an array instead.");
    return H;
  }
  function Xe(u, c, m) {
    if (u == null) return u;
    var x = [], k = 0;
    return Ye(u, x, "", "", function(T) {
      return c.call(m, T, k++);
    }), x;
  }
  function ze(u) {
    if (u._status === -1) {
      var c = u._result;
      c = c(), c.then(function(m) {
        (u._status === 0 || u._status === -1) && (u._status = 1, u._result = m);
      }, function(m) {
        (u._status === 0 || u._status === -1) && (u._status = 2, u._result = m);
      }), u._status === -1 && (u._status = 0, u._result = c);
    }
    if (u._status === 1) return u._result.default;
    throw u._result;
  }
  var le = { current: null }, L = { transition: null }, $ = { ReactCurrentDispatcher: le, ReactCurrentBatchConfig: L, ReactCurrentOwner: Ie };
  function P() {
    throw Error("act(...) is not supported in production builds of React.");
  }
  return se.Children = { map: Xe, forEach: function(u, c, m) {
    Xe(u, function() {
      c.apply(this, arguments);
    }, m);
  }, count: function(u) {
    var c = 0;
    return Xe(u, function() {
      c++;
    }), c;
  }, toArray: function(u) {
    return Xe(u, function(c) {
      return c;
    }) || [];
  }, only: function(u) {
    if (!De(u)) throw Error("React.Children.only expected to receive a single React element child.");
    return u;
  } }, se.Component = q, se.Fragment = f, se.Profiler = j, se.PureComponent = Ne, se.StrictMode = N, se.Suspense = I, se.__SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED = $, se.act = P, se.cloneElement = function(u, c, m) {
    if (u == null) throw Error("React.cloneElement(...): The argument must be a React element, but you passed " + u + ".");
    var x = Z({}, u.props), k = u.key, T = u.ref, H = u._owner;
    if (c != null) {
      if (c.ref !== void 0 && (T = c.ref, H = Ie.current), c.key !== void 0 && (k = "" + c.key), u.type && u.type.defaultProps) var Y = u.type.defaultProps;
      for (Q in c) Oe.call(c, Q) && !je.hasOwnProperty(Q) && (x[Q] = c[Q] === void 0 && Y !== void 0 ? Y[Q] : c[Q]);
    }
    var Q = arguments.length - 2;
    if (Q === 1) x.children = m;
    else if (1 < Q) {
      Y = Array(Q);
      for (var K = 0; K < Q; K++) Y[K] = arguments[K + 2];
      x.children = Y;
    }
    return { $$typeof: d, type: u.type, key: k, ref: T, props: x, _owner: H };
  }, se.createContext = function(u) {
    return u = { $$typeof: V, _currentValue: u, _currentValue2: u, _threadCount: 0, Provider: null, Consumer: null, _defaultValue: null, _globalName: null }, u.Provider = { $$typeof: C, _context: u }, u.Consumer = u;
  }, se.createElement = D, se.createFactory = function(u) {
    var c = D.bind(null, u);
    return c.type = u, c;
  }, se.createRef = function() {
    return { current: null };
  }, se.forwardRef = function(u) {
    return { $$typeof: ee, render: u };
  }, se.isValidElement = De, se.lazy = function(u) {
    return { $$typeof: O, _payload: { _status: -1, _result: u }, _init: ze };
  }, se.memo = function(u, c) {
    return { $$typeof: ce, type: u, compare: c === void 0 ? null : c };
  }, se.startTransition = function(u) {
    var c = L.transition;
    L.transition = {};
    try {
      u();
    } finally {
      L.transition = c;
    }
  }, se.unstable_act = P, se.useCallback = function(u, c) {
    return le.current.useCallback(u, c);
  }, se.useContext = function(u) {
    return le.current.useContext(u);
  }, se.useDebugValue = function() {
  }, se.useDeferredValue = function(u) {
    return le.current.useDeferredValue(u);
  }, se.useEffect = function(u, c) {
    return le.current.useEffect(u, c);
  }, se.useId = function() {
    return le.current.useId();
  }, se.useImperativeHandle = function(u, c, m) {
    return le.current.useImperativeHandle(u, c, m);
  }, se.useInsertionEffect = function(u, c) {
    return le.current.useInsertionEffect(u, c);
  }, se.useLayoutEffect = function(u, c) {
    return le.current.useLayoutEffect(u, c);
  }, se.useMemo = function(u, c) {
    return le.current.useMemo(u, c);
  }, se.useReducer = function(u, c, m) {
    return le.current.useReducer(u, c, m);
  }, se.useRef = function(u) {
    return le.current.useRef(u);
  }, se.useState = function(u) {
    return le.current.useState(u);
  }, se.useSyncExternalStore = function(u, c, m) {
    return le.current.useSyncExternalStore(u, c, m);
  }, se.useTransition = function() {
    return le.current.useTransition();
  }, se.version = "18.3.1", se;
}
var Ya;
function wu() {
  return Ya || (Ya = 1, pu.exports = ld()), pu.exports;
}
/**
 * @license React
 * react-jsx-runtime.production.min.js
 *
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
var Xa;
function id() {
  if (Xa) return vl;
  Xa = 1;
  var d = wu(), w = Symbol.for("react.element"), f = Symbol.for("react.fragment"), N = Object.prototype.hasOwnProperty, j = d.__SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED.ReactCurrentOwner, C = { key: !0, ref: !0, __self: !0, __source: !0 };
  function V(ee, I, ce) {
    var O, ie = {}, re = null, oe = null;
    ce !== void 0 && (re = "" + ce), I.key !== void 0 && (re = "" + I.key), I.ref !== void 0 && (oe = I.ref);
    for (O in I) N.call(I, O) && !C.hasOwnProperty(O) && (ie[O] = I[O]);
    if (ee && ee.defaultProps) for (O in I = ee.defaultProps, I) ie[O] === void 0 && (ie[O] = I[O]);
    return { $$typeof: w, type: ee, key: re, ref: oe, props: ie, _owner: j.current };
  }
  return vl.Fragment = f, vl.jsx = V, vl.jsxs = V, vl;
}
var Ga;
function od() {
  return Ga || (Ga = 1, du.exports = id()), du.exports;
}
var y = od(), ji = {}, hu = { exports: {} }, St = {}, mu = { exports: {} }, vu = {};
/**
 * @license React
 * scheduler.production.min.js
 *
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
var Za;
function ud() {
  return Za || (Za = 1, (function(d) {
    function w(L, $) {
      var P = L.length;
      L.push($);
      e: for (; 0 < P; ) {
        var u = P - 1 >>> 1, c = L[u];
        if (0 < j(c, $)) L[u] = $, L[P] = c, P = u;
        else break e;
      }
    }
    function f(L) {
      return L.length === 0 ? null : L[0];
    }
    function N(L) {
      if (L.length === 0) return null;
      var $ = L[0], P = L.pop();
      if (P !== $) {
        L[0] = P;
        e: for (var u = 0, c = L.length, m = c >>> 1; u < m; ) {
          var x = 2 * (u + 1) - 1, k = L[x], T = x + 1, H = L[T];
          if (0 > j(k, P)) T < c && 0 > j(H, k) ? (L[u] = H, L[T] = P, u = T) : (L[u] = k, L[x] = P, u = x);
          else if (T < c && 0 > j(H, P)) L[u] = H, L[T] = P, u = T;
          else break e;
        }
      }
      return $;
    }
    function j(L, $) {
      var P = L.sortIndex - $.sortIndex;
      return P !== 0 ? P : L.id - $.id;
    }
    if (typeof performance == "object" && typeof performance.now == "function") {
      var C = performance;
      d.unstable_now = function() {
        return C.now();
      };
    } else {
      var V = Date, ee = V.now();
      d.unstable_now = function() {
        return V.now() - ee;
      };
    }
    var I = [], ce = [], O = 1, ie = null, re = 3, oe = !1, Z = !1, te = !1, q = typeof setTimeout == "function" ? setTimeout : null, we = typeof clearTimeout == "function" ? clearTimeout : null, Ne = typeof setImmediate < "u" ? setImmediate : null;
    typeof navigator < "u" && navigator.scheduling !== void 0 && navigator.scheduling.isInputPending !== void 0 && navigator.scheduling.isInputPending.bind(navigator.scheduling);
    function Me(L) {
      for (var $ = f(ce); $ !== null; ) {
        if ($.callback === null) N(ce);
        else if ($.startTime <= L) N(ce), $.sortIndex = $.expirationTime, w(I, $);
        else break;
        $ = f(ce);
      }
    }
    function ve(L) {
      if (te = !1, Me(L), !Z) if (f(I) !== null) Z = !0, ze(Oe);
      else {
        var $ = f(ce);
        $ !== null && le(ve, $.startTime - L);
      }
    }
    function Oe(L, $) {
      Z = !1, te && (te = !1, we(D), D = -1), oe = !0;
      var P = re;
      try {
        for (Me($), ie = f(I); ie !== null && (!(ie.expirationTime > $) || L && !xe()); ) {
          var u = ie.callback;
          if (typeof u == "function") {
            ie.callback = null, re = ie.priorityLevel;
            var c = u(ie.expirationTime <= $);
            $ = d.unstable_now(), typeof c == "function" ? ie.callback = c : ie === f(I) && N(I), Me($);
          } else N(I);
          ie = f(I);
        }
        if (ie !== null) var m = !0;
        else {
          var x = f(ce);
          x !== null && le(ve, x.startTime - $), m = !1;
        }
        return m;
      } finally {
        ie = null, re = P, oe = !1;
      }
    }
    var Ie = !1, je = null, D = -1, Et = 5, De = -1;
    function xe() {
      return !(d.unstable_now() - De < Et);
    }
    function be() {
      if (je !== null) {
        var L = d.unstable_now();
        De = L;
        var $ = !0;
        try {
          $ = je(!0, L);
        } finally {
          $ ? Be() : (Ie = !1, je = null);
        }
      } else Ie = !1;
    }
    var Be;
    if (typeof Ne == "function") Be = function() {
      Ne(be);
    };
    else if (typeof MessageChannel < "u") {
      var Ye = new MessageChannel(), Xe = Ye.port2;
      Ye.port1.onmessage = be, Be = function() {
        Xe.postMessage(null);
      };
    } else Be = function() {
      q(be, 0);
    };
    function ze(L) {
      je = L, Ie || (Ie = !0, Be());
    }
    function le(L, $) {
      D = q(function() {
        L(d.unstable_now());
      }, $);
    }
    d.unstable_IdlePriority = 5, d.unstable_ImmediatePriority = 1, d.unstable_LowPriority = 4, d.unstable_NormalPriority = 3, d.unstable_Profiling = null, d.unstable_UserBlockingPriority = 2, d.unstable_cancelCallback = function(L) {
      L.callback = null;
    }, d.unstable_continueExecution = function() {
      Z || oe || (Z = !0, ze(Oe));
    }, d.unstable_forceFrameRate = function(L) {
      0 > L || 125 < L ? console.error("forceFrameRate takes a positive int between 0 and 125, forcing frame rates higher than 125 fps is not supported") : Et = 0 < L ? Math.floor(1e3 / L) : 5;
    }, d.unstable_getCurrentPriorityLevel = function() {
      return re;
    }, d.unstable_getFirstCallbackNode = function() {
      return f(I);
    }, d.unstable_next = function(L) {
      switch (re) {
        case 1:
        case 2:
        case 3:
          var $ = 3;
          break;
        default:
          $ = re;
      }
      var P = re;
      re = $;
      try {
        return L();
      } finally {
        re = P;
      }
    }, d.unstable_pauseExecution = function() {
    }, d.unstable_requestPaint = function() {
    }, d.unstable_runWithPriority = function(L, $) {
      switch (L) {
        case 1:
        case 2:
        case 3:
        case 4:
        case 5:
          break;
        default:
          L = 3;
      }
      var P = re;
      re = L;
      try {
        return $();
      } finally {
        re = P;
      }
    }, d.unstable_scheduleCallback = function(L, $, P) {
      var u = d.unstable_now();
      switch (typeof P == "object" && P !== null ? (P = P.delay, P = typeof P == "number" && 0 < P ? u + P : u) : P = u, L) {
        case 1:
          var c = -1;
          break;
        case 2:
          c = 250;
          break;
        case 5:
          c = 1073741823;
          break;
        case 4:
          c = 1e4;
          break;
        default:
          c = 5e3;
      }
      return c = P + c, L = { id: O++, callback: $, priorityLevel: L, startTime: P, expirationTime: c, sortIndex: -1 }, P > u ? (L.sortIndex = P, w(ce, L), f(I) === null && L === f(ce) && (te ? (we(D), D = -1) : te = !0, le(ve, P - u))) : (L.sortIndex = c, w(I, L), Z || oe || (Z = !0, ze(Oe))), L;
    }, d.unstable_shouldYield = xe, d.unstable_wrapCallback = function(L) {
      var $ = re;
      return function() {
        var P = re;
        re = $;
        try {
          return L.apply(this, arguments);
        } finally {
          re = P;
        }
      };
    };
  })(vu)), vu;
}
var qa;
function sd() {
  return qa || (qa = 1, mu.exports = ud()), mu.exports;
}
/**
 * @license React
 * react-dom.production.min.js
 *
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */
var Ja;
function ad() {
  if (Ja) return St;
  Ja = 1;
  var d = wu(), w = sd();
  function f(e) {
    for (var t = "https://reactjs.org/docs/error-decoder.html?invariant=" + e, n = 1; n < arguments.length; n++) t += "&args[]=" + encodeURIComponent(arguments[n]);
    return "Minified React error #" + e + "; visit " + t + " for the full message or use the non-minified dev environment for full errors and additional helpful warnings.";
  }
  var N = /* @__PURE__ */ new Set(), j = {};
  function C(e, t) {
    V(e, t), V(e + "Capture", t);
  }
  function V(e, t) {
    for (j[e] = t, e = 0; e < t.length; e++) N.add(t[e]);
  }
  var ee = !(typeof window > "u" || typeof window.document > "u" || typeof window.document.createElement > "u"), I = Object.prototype.hasOwnProperty, ce = /^[:A-Z_a-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD][:A-Z_a-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD\-.0-9\u00B7\u0300-\u036F\u203F-\u2040]*$/, O = {}, ie = {};
  function re(e) {
    return I.call(ie, e) ? !0 : I.call(O, e) ? !1 : ce.test(e) ? ie[e] = !0 : (O[e] = !0, !1);
  }
  function oe(e, t, n, r) {
    if (n !== null && n.type === 0) return !1;
    switch (typeof t) {
      case "function":
      case "symbol":
        return !0;
      case "boolean":
        return r ? !1 : n !== null ? !n.acceptsBooleans : (e = e.toLowerCase().slice(0, 5), e !== "data-" && e !== "aria-");
      default:
        return !1;
    }
  }
  function Z(e, t, n, r) {
    if (t === null || typeof t > "u" || oe(e, t, n, r)) return !0;
    if (r) return !1;
    if (n !== null) switch (n.type) {
      case 3:
        return !t;
      case 4:
        return t === !1;
      case 5:
        return isNaN(t);
      case 6:
        return isNaN(t) || 1 > t;
    }
    return !1;
  }
  function te(e, t, n, r, l, i, o) {
    this.acceptsBooleans = t === 2 || t === 3 || t === 4, this.attributeName = r, this.attributeNamespace = l, this.mustUseProperty = n, this.propertyName = e, this.type = t, this.sanitizeURL = i, this.removeEmptyString = o;
  }
  var q = {};
  "children dangerouslySetInnerHTML defaultValue defaultChecked innerHTML suppressContentEditableWarning suppressHydrationWarning style".split(" ").forEach(function(e) {
    q[e] = new te(e, 0, !1, e, null, !1, !1);
  }), [["acceptCharset", "accept-charset"], ["className", "class"], ["htmlFor", "for"], ["httpEquiv", "http-equiv"]].forEach(function(e) {
    var t = e[0];
    q[t] = new te(t, 1, !1, e[1], null, !1, !1);
  }), ["contentEditable", "draggable", "spellCheck", "value"].forEach(function(e) {
    q[e] = new te(e, 2, !1, e.toLowerCase(), null, !1, !1);
  }), ["autoReverse", "externalResourcesRequired", "focusable", "preserveAlpha"].forEach(function(e) {
    q[e] = new te(e, 2, !1, e, null, !1, !1);
  }), "allowFullScreen async autoFocus autoPlay controls default defer disabled disablePictureInPicture disableRemotePlayback formNoValidate hidden loop noModule noValidate open playsInline readOnly required reversed scoped seamless itemScope".split(" ").forEach(function(e) {
    q[e] = new te(e, 3, !1, e.toLowerCase(), null, !1, !1);
  }), ["checked", "multiple", "muted", "selected"].forEach(function(e) {
    q[e] = new te(e, 3, !0, e, null, !1, !1);
  }), ["capture", "download"].forEach(function(e) {
    q[e] = new te(e, 4, !1, e, null, !1, !1);
  }), ["cols", "rows", "size", "span"].forEach(function(e) {
    q[e] = new te(e, 6, !1, e, null, !1, !1);
  }), ["rowSpan", "start"].forEach(function(e) {
    q[e] = new te(e, 5, !1, e.toLowerCase(), null, !1, !1);
  });
  var we = /[\-:]([a-z])/g;
  function Ne(e) {
    return e[1].toUpperCase();
  }
  "accent-height alignment-baseline arabic-form baseline-shift cap-height clip-path clip-rule color-interpolation color-interpolation-filters color-profile color-rendering dominant-baseline enable-background fill-opacity fill-rule flood-color flood-opacity font-family font-size font-size-adjust font-stretch font-style font-variant font-weight glyph-name glyph-orientation-horizontal glyph-orientation-vertical horiz-adv-x horiz-origin-x image-rendering letter-spacing lighting-color marker-end marker-mid marker-start overline-position overline-thickness paint-order panose-1 pointer-events rendering-intent shape-rendering stop-color stop-opacity strikethrough-position strikethrough-thickness stroke-dasharray stroke-dashoffset stroke-linecap stroke-linejoin stroke-miterlimit stroke-opacity stroke-width text-anchor text-decoration text-rendering underline-position underline-thickness unicode-bidi unicode-range units-per-em v-alphabetic v-hanging v-ideographic v-mathematical vector-effect vert-adv-y vert-origin-x vert-origin-y word-spacing writing-mode xmlns:xlink x-height".split(" ").forEach(function(e) {
    var t = e.replace(
      we,
      Ne
    );
    q[t] = new te(t, 1, !1, e, null, !1, !1);
  }), "xlink:actuate xlink:arcrole xlink:role xlink:show xlink:title xlink:type".split(" ").forEach(function(e) {
    var t = e.replace(we, Ne);
    q[t] = new te(t, 1, !1, e, "http://www.w3.org/1999/xlink", !1, !1);
  }), ["xml:base", "xml:lang", "xml:space"].forEach(function(e) {
    var t = e.replace(we, Ne);
    q[t] = new te(t, 1, !1, e, "http://www.w3.org/XML/1998/namespace", !1, !1);
  }), ["tabIndex", "crossOrigin"].forEach(function(e) {
    q[e] = new te(e, 1, !1, e.toLowerCase(), null, !1, !1);
  }), q.xlinkHref = new te("xlinkHref", 1, !1, "xlink:href", "http://www.w3.org/1999/xlink", !0, !1), ["src", "href", "action", "formAction"].forEach(function(e) {
    q[e] = new te(e, 1, !1, e.toLowerCase(), null, !0, !0);
  });
  function Me(e, t, n, r) {
    var l = q.hasOwnProperty(t) ? q[t] : null;
    (l !== null ? l.type !== 0 : r || !(2 < t.length) || t[0] !== "o" && t[0] !== "O" || t[1] !== "n" && t[1] !== "N") && (Z(t, n, l, r) && (n = null), r || l === null ? re(t) && (n === null ? e.removeAttribute(t) : e.setAttribute(t, "" + n)) : l.mustUseProperty ? e[l.propertyName] = n === null ? l.type === 3 ? !1 : "" : n : (t = l.attributeName, r = l.attributeNamespace, n === null ? e.removeAttribute(t) : (l = l.type, n = l === 3 || l === 4 && n === !0 ? "" : "" + n, r ? e.setAttributeNS(r, t, n) : e.setAttribute(t, n))));
  }
  var ve = d.__SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED, Oe = Symbol.for("react.element"), Ie = Symbol.for("react.portal"), je = Symbol.for("react.fragment"), D = Symbol.for("react.strict_mode"), Et = Symbol.for("react.profiler"), De = Symbol.for("react.provider"), xe = Symbol.for("react.context"), be = Symbol.for("react.forward_ref"), Be = Symbol.for("react.suspense"), Ye = Symbol.for("react.suspense_list"), Xe = Symbol.for("react.memo"), ze = Symbol.for("react.lazy"), le = Symbol.for("react.offscreen"), L = Symbol.iterator;
  function $(e) {
    return e === null || typeof e != "object" ? null : (e = L && e[L] || e["@@iterator"], typeof e == "function" ? e : null);
  }
  var P = Object.assign, u;
  function c(e) {
    if (u === void 0) try {
      throw Error();
    } catch (n) {
      var t = n.stack.trim().match(/\n( *(at )?)/);
      u = t && t[1] || "";
    }
    return `
` + u + e;
  }
  var m = !1;
  function x(e, t) {
    if (!e || m) return "";
    m = !0;
    var n = Error.prepareStackTrace;
    Error.prepareStackTrace = void 0;
    try {
      if (t) if (t = function() {
        throw Error();
      }, Object.defineProperty(t.prototype, "props", { set: function() {
        throw Error();
      } }), typeof Reflect == "object" && Reflect.construct) {
        try {
          Reflect.construct(t, []);
        } catch (g) {
          var r = g;
        }
        Reflect.construct(e, [], t);
      } else {
        try {
          t.call();
        } catch (g) {
          r = g;
        }
        e.call(t.prototype);
      }
      else {
        try {
          throw Error();
        } catch (g) {
          r = g;
        }
        e();
      }
    } catch (g) {
      if (g && r && typeof g.stack == "string") {
        for (var l = g.stack.split(`
`), i = r.stack.split(`
`), o = l.length - 1, s = i.length - 1; 1 <= o && 0 <= s && l[o] !== i[s]; ) s--;
        for (; 1 <= o && 0 <= s; o--, s--) if (l[o] !== i[s]) {
          if (o !== 1 || s !== 1)
            do
              if (o--, s--, 0 > s || l[o] !== i[s]) {
                var a = `
` + l[o].replace(" at new ", " at ");
                return e.displayName && a.includes("<anonymous>") && (a = a.replace("<anonymous>", e.displayName)), a;
              }
            while (1 <= o && 0 <= s);
          break;
        }
      }
    } finally {
      m = !1, Error.prepareStackTrace = n;
    }
    return (e = e ? e.displayName || e.name : "") ? c(e) : "";
  }
  function k(e) {
    switch (e.tag) {
      case 5:
        return c(e.type);
      case 16:
        return c("Lazy");
      case 13:
        return c("Suspense");
      case 19:
        return c("SuspenseList");
      case 0:
      case 2:
      case 15:
        return e = x(e.type, !1), e;
      case 11:
        return e = x(e.type.render, !1), e;
      case 1:
        return e = x(e.type, !0), e;
      default:
        return "";
    }
  }
  function T(e) {
    if (e == null) return null;
    if (typeof e == "function") return e.displayName || e.name || null;
    if (typeof e == "string") return e;
    switch (e) {
      case je:
        return "Fragment";
      case Ie:
        return "Portal";
      case Et:
        return "Profiler";
      case D:
        return "StrictMode";
      case Be:
        return "Suspense";
      case Ye:
        return "SuspenseList";
    }
    if (typeof e == "object") switch (e.$$typeof) {
      case xe:
        return (e.displayName || "Context") + ".Consumer";
      case De:
        return (e._context.displayName || "Context") + ".Provider";
      case be:
        var t = e.render;
        return e = e.displayName, e || (e = t.displayName || t.name || "", e = e !== "" ? "ForwardRef(" + e + ")" : "ForwardRef"), e;
      case Xe:
        return t = e.displayName || null, t !== null ? t : T(e.type) || "Memo";
      case ze:
        t = e._payload, e = e._init;
        try {
          return T(e(t));
        } catch {
        }
    }
    return null;
  }
  function H(e) {
    var t = e.type;
    switch (e.tag) {
      case 24:
        return "Cache";
      case 9:
        return (t.displayName || "Context") + ".Consumer";
      case 10:
        return (t._context.displayName || "Context") + ".Provider";
      case 18:
        return "DehydratedFragment";
      case 11:
        return e = t.render, e = e.displayName || e.name || "", t.displayName || (e !== "" ? "ForwardRef(" + e + ")" : "ForwardRef");
      case 7:
        return "Fragment";
      case 5:
        return t;
      case 4:
        return "Portal";
      case 3:
        return "Root";
      case 6:
        return "Text";
      case 16:
        return T(t);
      case 8:
        return t === D ? "StrictMode" : "Mode";
      case 22:
        return "Offscreen";
      case 12:
        return "Profiler";
      case 21:
        return "Scope";
      case 13:
        return "Suspense";
      case 19:
        return "SuspenseList";
      case 25:
        return "TracingMarker";
      case 1:
      case 0:
      case 17:
      case 2:
      case 14:
      case 15:
        if (typeof t == "function") return t.displayName || t.name || null;
        if (typeof t == "string") return t;
    }
    return null;
  }
  function Y(e) {
    switch (typeof e) {
      case "boolean":
      case "number":
      case "string":
      case "undefined":
        return e;
      case "object":
        return e;
      default:
        return "";
    }
  }
  function Q(e) {
    var t = e.type;
    return (e = e.nodeName) && e.toLowerCase() === "input" && (t === "checkbox" || t === "radio");
  }
  function K(e) {
    var t = Q(e) ? "checked" : "value", n = Object.getOwnPropertyDescriptor(e.constructor.prototype, t), r = "" + e[t];
    if (!e.hasOwnProperty(t) && typeof n < "u" && typeof n.get == "function" && typeof n.set == "function") {
      var l = n.get, i = n.set;
      return Object.defineProperty(e, t, { configurable: !0, get: function() {
        return l.call(this);
      }, set: function(o) {
        r = "" + o, i.call(this, o);
      } }), Object.defineProperty(e, t, { enumerable: n.enumerable }), { getValue: function() {
        return r;
      }, setValue: function(o) {
        r = "" + o;
      }, stopTracking: function() {
        e._valueTracker = null, delete e[t];
      } };
    }
  }
  function ne(e) {
    e._valueTracker || (e._valueTracker = K(e));
  }
  function ae(e) {
    if (!e) return !1;
    var t = e._valueTracker;
    if (!t) return !0;
    var n = t.getValue(), r = "";
    return e && (r = Q(e) ? e.checked ? "true" : "false" : e.value), e = r, e !== n ? (t.setValue(e), !0) : !1;
  }
  function ke(e) {
    if (e = e || (typeof document < "u" ? document : void 0), typeof e > "u") return null;
    try {
      return e.activeElement || e.body;
    } catch {
      return e.body;
    }
  }
  function Ve(e, t) {
    var n = t.checked;
    return P({}, t, { defaultChecked: void 0, defaultValue: void 0, value: void 0, checked: n ?? e._wrapperState.initialChecked });
  }
  function me(e, t) {
    var n = t.defaultValue == null ? "" : t.defaultValue, r = t.checked != null ? t.checked : t.defaultChecked;
    n = Y(t.value != null ? t.value : n), e._wrapperState = { initialChecked: r, initialValue: n, controlled: t.type === "checkbox" || t.type === "radio" ? t.checked != null : t.value != null };
  }
  function rn(e, t) {
    t = t.checked, t != null && Me(e, "checked", t, !1);
  }
  function Ee(e, t) {
    rn(e, t);
    var n = Y(t.value), r = t.type;
    if (n != null) r === "number" ? (n === 0 && e.value === "" || e.value != n) && (e.value = "" + n) : e.value !== "" + n && (e.value = "" + n);
    else if (r === "submit" || r === "reset") {
      e.removeAttribute("value");
      return;
    }
    t.hasOwnProperty("value") ? _e(e, t.type, n) : t.hasOwnProperty("defaultValue") && _e(e, t.type, Y(t.defaultValue)), t.checked == null && t.defaultChecked != null && (e.defaultChecked = !!t.defaultChecked);
  }
  function et(e, t, n) {
    if (t.hasOwnProperty("value") || t.hasOwnProperty("defaultValue")) {
      var r = t.type;
      if (!(r !== "submit" && r !== "reset" || t.value !== void 0 && t.value !== null)) return;
      t = "" + e._wrapperState.initialValue, n || t === e.value || (e.value = t), e.defaultValue = t;
    }
    n = e.name, n !== "" && (e.name = ""), e.defaultChecked = !!e._wrapperState.initialChecked, n !== "" && (e.name = n);
  }
  function _e(e, t, n) {
    (t !== "number" || ke(e.ownerDocument) !== e) && (n == null ? e.defaultValue = "" + e._wrapperState.initialValue : e.defaultValue !== "" + n && (e.defaultValue = "" + n));
  }
  var fe = Array.isArray;
  function dt(e, t, n, r) {
    if (e = e.options, t) {
      t = {};
      for (var l = 0; l < n.length; l++) t["$" + n[l]] = !0;
      for (n = 0; n < e.length; n++) l = t.hasOwnProperty("$" + e[n].value), e[n].selected !== l && (e[n].selected = l), l && r && (e[n].defaultSelected = !0);
    } else {
      for (n = "" + Y(n), t = null, l = 0; l < e.length; l++) {
        if (e[l].value === n) {
          e[l].selected = !0, r && (e[l].defaultSelected = !0);
          return;
        }
        t !== null || e[l].disabled || (t = e[l]);
      }
      t !== null && (t.selected = !0);
    }
  }
  function _t(e, t) {
    if (t.dangerouslySetInnerHTML != null) throw Error(f(91));
    return P({}, t, { value: void 0, defaultValue: void 0, children: "" + e._wrapperState.initialValue });
  }
  function Ft(e, t) {
    var n = t.value;
    if (n == null) {
      if (n = t.children, t = t.defaultValue, n != null) {
        if (t != null) throw Error(f(92));
        if (fe(n)) {
          if (1 < n.length) throw Error(f(93));
          n = n[0];
        }
        t = n;
      }
      t == null && (t = ""), n = t;
    }
    e._wrapperState = { initialValue: Y(n) };
  }
  function At(e, t) {
    var n = Y(t.value), r = Y(t.defaultValue);
    n != null && (n = "" + n, n !== e.value && (e.value = n), t.defaultValue == null && e.defaultValue !== n && (e.defaultValue = n)), r != null && (e.defaultValue = "" + r);
  }
  function ln(e) {
    var t = e.textContent;
    t === e._wrapperState.initialValue && t !== "" && t !== null && (e.value = t);
  }
  function pt(e) {
    switch (e) {
      case "svg":
        return "http://www.w3.org/2000/svg";
      case "math":
        return "http://www.w3.org/1998/Math/MathML";
      default:
        return "http://www.w3.org/1999/xhtml";
    }
  }
  function on(e, t) {
    return e == null || e === "http://www.w3.org/1999/xhtml" ? pt(t) : e === "http://www.w3.org/2000/svg" && t === "foreignObject" ? "http://www.w3.org/1999/xhtml" : e;
  }
  var Yt, wn = (function(e) {
    return typeof MSApp < "u" && MSApp.execUnsafeLocalFunction ? function(t, n, r, l) {
      MSApp.execUnsafeLocalFunction(function() {
        return e(t, n, r, l);
      });
    } : e;
  })(function(e, t) {
    if (e.namespaceURI !== "http://www.w3.org/2000/svg" || "innerHTML" in e) e.innerHTML = t;
    else {
      for (Yt = Yt || document.createElement("div"), Yt.innerHTML = "<svg>" + t.valueOf().toString() + "</svg>", t = Yt.firstChild; e.firstChild; ) e.removeChild(e.firstChild);
      for (; t.firstChild; ) e.appendChild(t.firstChild);
    }
  });
  function tt(e, t) {
    if (t) {
      var n = e.firstChild;
      if (n && n === e.lastChild && n.nodeType === 3) {
        n.nodeValue = t;
        return;
      }
    }
    e.textContent = t;
  }
  var Xt = {
    animationIterationCount: !0,
    aspectRatio: !0,
    borderImageOutset: !0,
    borderImageSlice: !0,
    borderImageWidth: !0,
    boxFlex: !0,
    boxFlexGroup: !0,
    boxOrdinalGroup: !0,
    columnCount: !0,
    columns: !0,
    flex: !0,
    flexGrow: !0,
    flexPositive: !0,
    flexShrink: !0,
    flexNegative: !0,
    flexOrder: !0,
    gridArea: !0,
    gridRow: !0,
    gridRowEnd: !0,
    gridRowSpan: !0,
    gridRowStart: !0,
    gridColumn: !0,
    gridColumnEnd: !0,
    gridColumnSpan: !0,
    gridColumnStart: !0,
    fontWeight: !0,
    lineClamp: !0,
    lineHeight: !0,
    opacity: !0,
    order: !0,
    orphans: !0,
    tabSize: !0,
    widows: !0,
    zIndex: !0,
    zoom: !0,
    fillOpacity: !0,
    floodOpacity: !0,
    stopOpacity: !0,
    strokeDasharray: !0,
    strokeDashoffset: !0,
    strokeMiterlimit: !0,
    strokeOpacity: !0,
    strokeWidth: !0
  }, Pi = ["Webkit", "ms", "Moz", "O"];
  Object.keys(Xt).forEach(function(e) {
    Pi.forEach(function(t) {
      t = t + e.charAt(0).toUpperCase() + e.substring(1), Xt[t] = Xt[e];
    });
  });
  function Tr(e, t, n) {
    return t == null || typeof t == "boolean" || t === "" ? "" : n || typeof t != "number" || t === 0 || Xt.hasOwnProperty(e) && Xt[e] ? ("" + t).trim() : t + "px";
  }
  function un(e, t) {
    e = e.style;
    for (var n in t) if (t.hasOwnProperty(n)) {
      var r = n.indexOf("--") === 0, l = Tr(n, t[n], r);
      n === "float" && (n = "cssFloat"), r ? e.setProperty(n, l) : e[n] = l;
    }
  }
  var Wn = P({ menuitem: !0 }, { area: !0, base: !0, br: !0, col: !0, embed: !0, hr: !0, img: !0, input: !0, keygen: !0, link: !0, meta: !0, param: !0, source: !0, track: !0, wbr: !0 });
  function sn(e, t) {
    if (t) {
      if (Wn[e] && (t.children != null || t.dangerouslySetInnerHTML != null)) throw Error(f(137, e));
      if (t.dangerouslySetInnerHTML != null) {
        if (t.children != null) throw Error(f(60));
        if (typeof t.dangerouslySetInnerHTML != "object" || !("__html" in t.dangerouslySetInnerHTML)) throw Error(f(61));
      }
      if (t.style != null && typeof t.style != "object") throw Error(f(62));
    }
  }
  function an(e, t) {
    if (e.indexOf("-") === -1) return typeof t.is == "string";
    switch (e) {
      case "annotation-xml":
      case "color-profile":
      case "font-face":
      case "font-face-src":
      case "font-face-uri":
      case "font-face-format":
      case "font-face-name":
      case "missing-glyph":
        return !1;
      default:
        return !0;
    }
  }
  var Gt = null;
  function Dt(e) {
    return e = e.target || e.srcElement || window, e.correspondingUseElement && (e = e.correspondingUseElement), e.nodeType === 3 ? e.parentNode : e;
  }
  var Bn = null, ht = null, Ut = null;
  function rr(e) {
    if (e = tl(e)) {
      if (typeof Bn != "function") throw Error(f(280));
      var t = e.stateNode;
      t && (t = Bl(t), Bn(e.stateNode, e.type, t));
    }
  }
  function Mr(e) {
    ht ? Ut ? Ut.push(e) : Ut = [e] : ht = e;
  }
  function wl() {
    if (ht) {
      var e = ht, t = Ut;
      if (Ut = ht = null, rr(e), t) for (e = 0; e < t.length; e++) rr(t[e]);
    }
  }
  function xl(e, t) {
    return e(t);
  }
  function R() {
  }
  var ue = !1;
  function b(e, t, n) {
    if (ue) return e(t, n);
    ue = !0;
    try {
      return xl(e, t, n);
    } finally {
      ue = !1, (ht !== null || Ut !== null) && (R(), wl());
    }
  }
  function Re(e, t) {
    var n = e.stateNode;
    if (n === null) return null;
    var r = Bl(n);
    if (r === null) return null;
    n = r[t];
    e: switch (t) {
      case "onClick":
      case "onClickCapture":
      case "onDoubleClick":
      case "onDoubleClickCapture":
      case "onMouseDown":
      case "onMouseDownCapture":
      case "onMouseMove":
      case "onMouseMoveCapture":
      case "onMouseUp":
      case "onMouseUpCapture":
      case "onMouseEnter":
        (r = !r.disabled) || (e = e.type, r = !(e === "button" || e === "input" || e === "select" || e === "textarea")), e = !r;
        break e;
      default:
        e = !1;
    }
    if (e) return null;
    if (n && typeof n != "function") throw Error(f(231, t, typeof n));
    return n;
  }
  var Se = !1;
  if (ee) try {
    var nt = {};
    Object.defineProperty(nt, "passive", { get: function() {
      Se = !0;
    } }), window.addEventListener("test", nt, nt), window.removeEventListener("test", nt, nt);
  } catch {
    Se = !1;
  }
  function Ct(e, t, n, r, l, i, o, s, a) {
    var g = Array.prototype.slice.call(arguments, 3);
    try {
      t.apply(n, g);
    } catch (E) {
      this.onError(E);
    }
  }
  var at = !1, de = null, Ge = !1, Zt = null, xn = { onError: function(e) {
    at = !0, de = e;
  } };
  function kn(e, t, n, r, l, i, o, s, a) {
    at = !1, de = null, Ct.apply(xn, arguments);
  }
  function lr(e, t, n, r, l, i, o, s, a) {
    if (kn.apply(this, arguments), at) {
      if (at) {
        var g = de;
        at = !1, de = null;
      } else throw Error(f(198));
      Ge || (Ge = !0, Zt = g);
    }
  }
  function mt(e) {
    var t = e, n = e;
    if (e.alternate) for (; t.return; ) t = t.return;
    else {
      e = t;
      do
        t = e, (t.flags & 4098) !== 0 && (n = t.return), e = t.return;
      while (e);
    }
    return t.tag === 3 ? n : null;
  }
  function ir(e) {
    if (e.tag === 13) {
      var t = e.memoizedState;
      if (t === null && (e = e.alternate, e !== null && (t = e.memoizedState)), t !== null) return t.dehydrated;
    }
    return null;
  }
  function or(e) {
    if (mt(e) !== e) throw Error(f(188));
  }
  function kl(e) {
    var t = e.alternate;
    if (!t) {
      if (t = mt(e), t === null) throw Error(f(188));
      return t !== e ? null : e;
    }
    for (var n = e, r = t; ; ) {
      var l = n.return;
      if (l === null) break;
      var i = l.alternate;
      if (i === null) {
        if (r = l.return, r !== null) {
          n = r;
          continue;
        }
        break;
      }
      if (l.child === i.child) {
        for (i = l.child; i; ) {
          if (i === n) return or(l), e;
          if (i === r) return or(l), t;
          i = i.sibling;
        }
        throw Error(f(188));
      }
      if (n.return !== r.return) n = l, r = i;
      else {
        for (var o = !1, s = l.child; s; ) {
          if (s === n) {
            o = !0, n = l, r = i;
            break;
          }
          if (s === r) {
            o = !0, r = l, n = i;
            break;
          }
          s = s.sibling;
        }
        if (!o) {
          for (s = i.child; s; ) {
            if (s === n) {
              o = !0, n = i, r = l;
              break;
            }
            if (s === r) {
              o = !0, r = i, n = l;
              break;
            }
            s = s.sibling;
          }
          if (!o) throw Error(f(189));
        }
      }
      if (n.alternate !== r) throw Error(f(190));
    }
    if (n.tag !== 3) throw Error(f(188));
    return n.stateNode.current === n ? e : t;
  }
  function Or(e) {
    return e = kl(e), e !== null ? Ir(e) : null;
  }
  function Ir(e) {
    if (e.tag === 5 || e.tag === 6) return e;
    for (e = e.child; e !== null; ) {
      var t = Ir(e);
      if (t !== null) return t;
      e = e.sibling;
    }
    return null;
  }
  var Fr = w.unstable_scheduleCallback, ye = w.unstable_cancelCallback, vt = w.unstable_shouldYield, cn = w.unstable_requestPaint, $e = w.unstable_now, vc = w.unstable_getCurrentPriorityLevel, Ri = w.unstable_ImmediatePriority, ku = w.unstable_UserBlockingPriority, Sl = w.unstable_NormalPriority, yc = w.unstable_LowPriority, Su = w.unstable_IdlePriority, El = null, qt = null;
  function gc(e) {
    if (qt && typeof qt.onCommitFiberRoot == "function") try {
      qt.onCommitFiberRoot(El, e, void 0, (e.current.flags & 128) === 128);
    } catch {
    }
  }
  var $t = Math.clz32 ? Math.clz32 : kc, wc = Math.log, xc = Math.LN2;
  function kc(e) {
    return e >>>= 0, e === 0 ? 32 : 31 - (wc(e) / xc | 0) | 0;
  }
  var _l = 64, Cl = 4194304;
  function Ar(e) {
    switch (e & -e) {
      case 1:
        return 1;
      case 2:
        return 2;
      case 4:
        return 4;
      case 8:
        return 8;
      case 16:
        return 16;
      case 32:
        return 32;
      case 64:
      case 128:
      case 256:
      case 512:
      case 1024:
      case 2048:
      case 4096:
      case 8192:
      case 16384:
      case 32768:
      case 65536:
      case 131072:
      case 262144:
      case 524288:
      case 1048576:
      case 2097152:
        return e & 4194240;
      case 4194304:
      case 8388608:
      case 16777216:
      case 33554432:
      case 67108864:
        return e & 130023424;
      case 134217728:
        return 134217728;
      case 268435456:
        return 268435456;
      case 536870912:
        return 536870912;
      case 1073741824:
        return 1073741824;
      default:
        return e;
    }
  }
  function Nl(e, t) {
    var n = e.pendingLanes;
    if (n === 0) return 0;
    var r = 0, l = e.suspendedLanes, i = e.pingedLanes, o = n & 268435455;
    if (o !== 0) {
      var s = o & ~l;
      s !== 0 ? r = Ar(s) : (i &= o, i !== 0 && (r = Ar(i)));
    } else o = n & ~l, o !== 0 ? r = Ar(o) : i !== 0 && (r = Ar(i));
    if (r === 0) return 0;
    if (t !== 0 && t !== r && (t & l) === 0 && (l = r & -r, i = t & -t, l >= i || l === 16 && (i & 4194240) !== 0)) return t;
    if ((r & 4) !== 0 && (r |= n & 16), t = e.entangledLanes, t !== 0) for (e = e.entanglements, t &= r; 0 < t; ) n = 31 - $t(t), l = 1 << n, r |= e[n], t &= ~l;
    return r;
  }
  function Sc(e, t) {
    switch (e) {
      case 1:
      case 2:
      case 4:
        return t + 250;
      case 8:
      case 16:
      case 32:
      case 64:
      case 128:
      case 256:
      case 512:
      case 1024:
      case 2048:
      case 4096:
      case 8192:
      case 16384:
      case 32768:
      case 65536:
      case 131072:
      case 262144:
      case 524288:
      case 1048576:
      case 2097152:
        return t + 5e3;
      case 4194304:
      case 8388608:
      case 16777216:
      case 33554432:
      case 67108864:
        return -1;
      case 134217728:
      case 268435456:
      case 536870912:
      case 1073741824:
        return -1;
      default:
        return -1;
    }
  }
  function Ec(e, t) {
    for (var n = e.suspendedLanes, r = e.pingedLanes, l = e.expirationTimes, i = e.pendingLanes; 0 < i; ) {
      var o = 31 - $t(i), s = 1 << o, a = l[o];
      a === -1 ? ((s & n) === 0 || (s & r) !== 0) && (l[o] = Sc(s, t)) : a <= t && (e.expiredLanes |= s), i &= ~s;
    }
  }
  function Ti(e) {
    return e = e.pendingLanes & -1073741825, e !== 0 ? e : e & 1073741824 ? 1073741824 : 0;
  }
  function Eu() {
    var e = _l;
    return _l <<= 1, (_l & 4194240) === 0 && (_l = 64), e;
  }
  function Mi(e) {
    for (var t = [], n = 0; 31 > n; n++) t.push(e);
    return t;
  }
  function Dr(e, t, n) {
    e.pendingLanes |= t, t !== 536870912 && (e.suspendedLanes = 0, e.pingedLanes = 0), e = e.eventTimes, t = 31 - $t(t), e[t] = n;
  }
  function _c(e, t) {
    var n = e.pendingLanes & ~t;
    e.pendingLanes = t, e.suspendedLanes = 0, e.pingedLanes = 0, e.expiredLanes &= t, e.mutableReadLanes &= t, e.entangledLanes &= t, t = e.entanglements;
    var r = e.eventTimes;
    for (e = e.expirationTimes; 0 < n; ) {
      var l = 31 - $t(n), i = 1 << l;
      t[l] = 0, r[l] = -1, e[l] = -1, n &= ~i;
    }
  }
  function Oi(e, t) {
    var n = e.entangledLanes |= t;
    for (e = e.entanglements; n; ) {
      var r = 31 - $t(n), l = 1 << r;
      l & t | e[r] & t && (e[r] |= t), n &= ~l;
    }
  }
  var ge = 0;
  function _u(e) {
    return e &= -e, 1 < e ? 4 < e ? (e & 268435455) !== 0 ? 16 : 536870912 : 4 : 1;
  }
  var Cu, Ii, Nu, ju, zu, Fi = !1, jl = [], Sn = null, En = null, _n = null, Ur = /* @__PURE__ */ new Map(), $r = /* @__PURE__ */ new Map(), Cn = [], Cc = "mousedown mouseup touchcancel touchend touchstart auxclick dblclick pointercancel pointerdown pointerup dragend dragstart drop compositionend compositionstart keydown keypress keyup input textInput copy cut paste click change contextmenu reset submit".split(" ");
  function Lu(e, t) {
    switch (e) {
      case "focusin":
      case "focusout":
        Sn = null;
        break;
      case "dragenter":
      case "dragleave":
        En = null;
        break;
      case "mouseover":
      case "mouseout":
        _n = null;
        break;
      case "pointerover":
      case "pointerout":
        Ur.delete(t.pointerId);
        break;
      case "gotpointercapture":
      case "lostpointercapture":
        $r.delete(t.pointerId);
    }
  }
  function Wr(e, t, n, r, l, i) {
    return e === null || e.nativeEvent !== i ? (e = { blockedOn: t, domEventName: n, eventSystemFlags: r, nativeEvent: i, targetContainers: [l] }, t !== null && (t = tl(t), t !== null && Ii(t)), e) : (e.eventSystemFlags |= r, t = e.targetContainers, l !== null && t.indexOf(l) === -1 && t.push(l), e);
  }
  function Nc(e, t, n, r, l) {
    switch (t) {
      case "focusin":
        return Sn = Wr(Sn, e, t, n, r, l), !0;
      case "dragenter":
        return En = Wr(En, e, t, n, r, l), !0;
      case "mouseover":
        return _n = Wr(_n, e, t, n, r, l), !0;
      case "pointerover":
        var i = l.pointerId;
        return Ur.set(i, Wr(Ur.get(i) || null, e, t, n, r, l)), !0;
      case "gotpointercapture":
        return i = l.pointerId, $r.set(i, Wr($r.get(i) || null, e, t, n, r, l)), !0;
    }
    return !1;
  }
  function Pu(e) {
    var t = Hn(e.target);
    if (t !== null) {
      var n = mt(t);
      if (n !== null) {
        if (t = n.tag, t === 13) {
          if (t = ir(n), t !== null) {
            e.blockedOn = t, zu(e.priority, function() {
              Nu(n);
            });
            return;
          }
        } else if (t === 3 && n.stateNode.current.memoizedState.isDehydrated) {
          e.blockedOn = n.tag === 3 ? n.stateNode.containerInfo : null;
          return;
        }
      }
    }
    e.blockedOn = null;
  }
  function zl(e) {
    if (e.blockedOn !== null) return !1;
    for (var t = e.targetContainers; 0 < t.length; ) {
      var n = Di(e.domEventName, e.eventSystemFlags, t[0], e.nativeEvent);
      if (n === null) {
        n = e.nativeEvent;
        var r = new n.constructor(n.type, n);
        Gt = r, n.target.dispatchEvent(r), Gt = null;
      } else return t = tl(n), t !== null && Ii(t), e.blockedOn = n, !1;
      t.shift();
    }
    return !0;
  }
  function Ru(e, t, n) {
    zl(e) && n.delete(t);
  }
  function jc() {
    Fi = !1, Sn !== null && zl(Sn) && (Sn = null), En !== null && zl(En) && (En = null), _n !== null && zl(_n) && (_n = null), Ur.forEach(Ru), $r.forEach(Ru);
  }
  function Br(e, t) {
    e.blockedOn === t && (e.blockedOn = null, Fi || (Fi = !0, w.unstable_scheduleCallback(w.unstable_NormalPriority, jc)));
  }
  function Hr(e) {
    function t(l) {
      return Br(l, e);
    }
    if (0 < jl.length) {
      Br(jl[0], e);
      for (var n = 1; n < jl.length; n++) {
        var r = jl[n];
        r.blockedOn === e && (r.blockedOn = null);
      }
    }
    for (Sn !== null && Br(Sn, e), En !== null && Br(En, e), _n !== null && Br(_n, e), Ur.forEach(t), $r.forEach(t), n = 0; n < Cn.length; n++) r = Cn[n], r.blockedOn === e && (r.blockedOn = null);
    for (; 0 < Cn.length && (n = Cn[0], n.blockedOn === null); ) Pu(n), n.blockedOn === null && Cn.shift();
  }
  var ur = ve.ReactCurrentBatchConfig, Ll = !0;
  function zc(e, t, n, r) {
    var l = ge, i = ur.transition;
    ur.transition = null;
    try {
      ge = 1, Ai(e, t, n, r);
    } finally {
      ge = l, ur.transition = i;
    }
  }
  function Lc(e, t, n, r) {
    var l = ge, i = ur.transition;
    ur.transition = null;
    try {
      ge = 4, Ai(e, t, n, r);
    } finally {
      ge = l, ur.transition = i;
    }
  }
  function Ai(e, t, n, r) {
    if (Ll) {
      var l = Di(e, t, n, r);
      if (l === null) to(e, t, r, Pl, n), Lu(e, r);
      else if (Nc(l, e, t, n, r)) r.stopPropagation();
      else if (Lu(e, r), t & 4 && -1 < Cc.indexOf(e)) {
        for (; l !== null; ) {
          var i = tl(l);
          if (i !== null && Cu(i), i = Di(e, t, n, r), i === null && to(e, t, r, Pl, n), i === l) break;
          l = i;
        }
        l !== null && r.stopPropagation();
      } else to(e, t, r, null, n);
    }
  }
  var Pl = null;
  function Di(e, t, n, r) {
    if (Pl = null, e = Dt(r), e = Hn(e), e !== null) if (t = mt(e), t === null) e = null;
    else if (n = t.tag, n === 13) {
      if (e = ir(t), e !== null) return e;
      e = null;
    } else if (n === 3) {
      if (t.stateNode.current.memoizedState.isDehydrated) return t.tag === 3 ? t.stateNode.containerInfo : null;
      e = null;
    } else t !== e && (e = null);
    return Pl = e, null;
  }
  function Tu(e) {
    switch (e) {
      case "cancel":
      case "click":
      case "close":
      case "contextmenu":
      case "copy":
      case "cut":
      case "auxclick":
      case "dblclick":
      case "dragend":
      case "dragstart":
      case "drop":
      case "focusin":
      case "focusout":
      case "input":
      case "invalid":
      case "keydown":
      case "keypress":
      case "keyup":
      case "mousedown":
      case "mouseup":
      case "paste":
      case "pause":
      case "play":
      case "pointercancel":
      case "pointerdown":
      case "pointerup":
      case "ratechange":
      case "reset":
      case "resize":
      case "seeked":
      case "submit":
      case "touchcancel":
      case "touchend":
      case "touchstart":
      case "volumechange":
      case "change":
      case "selectionchange":
      case "textInput":
      case "compositionstart":
      case "compositionend":
      case "compositionupdate":
      case "beforeblur":
      case "afterblur":
      case "beforeinput":
      case "blur":
      case "fullscreenchange":
      case "focus":
      case "hashchange":
      case "popstate":
      case "select":
      case "selectstart":
        return 1;
      case "drag":
      case "dragenter":
      case "dragexit":
      case "dragleave":
      case "dragover":
      case "mousemove":
      case "mouseout":
      case "mouseover":
      case "pointermove":
      case "pointerout":
      case "pointerover":
      case "scroll":
      case "toggle":
      case "touchmove":
      case "wheel":
      case "mouseenter":
      case "mouseleave":
      case "pointerenter":
      case "pointerleave":
        return 4;
      case "message":
        switch (vc()) {
          case Ri:
            return 1;
          case ku:
            return 4;
          case Sl:
          case yc:
            return 16;
          case Su:
            return 536870912;
          default:
            return 16;
        }
      default:
        return 16;
    }
  }
  var Nn = null, Ui = null, Rl = null;
  function Mu() {
    if (Rl) return Rl;
    var e, t = Ui, n = t.length, r, l = "value" in Nn ? Nn.value : Nn.textContent, i = l.length;
    for (e = 0; e < n && t[e] === l[e]; e++) ;
    var o = n - e;
    for (r = 1; r <= o && t[n - r] === l[i - r]; r++) ;
    return Rl = l.slice(e, 1 < r ? 1 - r : void 0);
  }
  function Tl(e) {
    var t = e.keyCode;
    return "charCode" in e ? (e = e.charCode, e === 0 && t === 13 && (e = 13)) : e = t, e === 10 && (e = 13), 32 <= e || e === 13 ? e : 0;
  }
  function Ml() {
    return !0;
  }
  function Ou() {
    return !1;
  }
  function Nt(e) {
    function t(n, r, l, i, o) {
      this._reactName = n, this._targetInst = l, this.type = r, this.nativeEvent = i, this.target = o, this.currentTarget = null;
      for (var s in e) e.hasOwnProperty(s) && (n = e[s], this[s] = n ? n(i) : i[s]);
      return this.isDefaultPrevented = (i.defaultPrevented != null ? i.defaultPrevented : i.returnValue === !1) ? Ml : Ou, this.isPropagationStopped = Ou, this;
    }
    return P(t.prototype, { preventDefault: function() {
      this.defaultPrevented = !0;
      var n = this.nativeEvent;
      n && (n.preventDefault ? n.preventDefault() : typeof n.returnValue != "unknown" && (n.returnValue = !1), this.isDefaultPrevented = Ml);
    }, stopPropagation: function() {
      var n = this.nativeEvent;
      n && (n.stopPropagation ? n.stopPropagation() : typeof n.cancelBubble != "unknown" && (n.cancelBubble = !0), this.isPropagationStopped = Ml);
    }, persist: function() {
    }, isPersistent: Ml }), t;
  }
  var sr = { eventPhase: 0, bubbles: 0, cancelable: 0, timeStamp: function(e) {
    return e.timeStamp || Date.now();
  }, defaultPrevented: 0, isTrusted: 0 }, $i = Nt(sr), Vr = P({}, sr, { view: 0, detail: 0 }), Pc = Nt(Vr), Wi, Bi, Qr, Ol = P({}, Vr, { screenX: 0, screenY: 0, clientX: 0, clientY: 0, pageX: 0, pageY: 0, ctrlKey: 0, shiftKey: 0, altKey: 0, metaKey: 0, getModifierState: Vi, button: 0, buttons: 0, relatedTarget: function(e) {
    return e.relatedTarget === void 0 ? e.fromElement === e.srcElement ? e.toElement : e.fromElement : e.relatedTarget;
  }, movementX: function(e) {
    return "movementX" in e ? e.movementX : (e !== Qr && (Qr && e.type === "mousemove" ? (Wi = e.screenX - Qr.screenX, Bi = e.screenY - Qr.screenY) : Bi = Wi = 0, Qr = e), Wi);
  }, movementY: function(e) {
    return "movementY" in e ? e.movementY : Bi;
  } }), Iu = Nt(Ol), Rc = P({}, Ol, { dataTransfer: 0 }), Tc = Nt(Rc), Mc = P({}, Vr, { relatedTarget: 0 }), Hi = Nt(Mc), Oc = P({}, sr, { animationName: 0, elapsedTime: 0, pseudoElement: 0 }), Ic = Nt(Oc), Fc = P({}, sr, { clipboardData: function(e) {
    return "clipboardData" in e ? e.clipboardData : window.clipboardData;
  } }), Ac = Nt(Fc), Dc = P({}, sr, { data: 0 }), Fu = Nt(Dc), Uc = {
    Esc: "Escape",
    Spacebar: " ",
    Left: "ArrowLeft",
    Up: "ArrowUp",
    Right: "ArrowRight",
    Down: "ArrowDown",
    Del: "Delete",
    Win: "OS",
    Menu: "ContextMenu",
    Apps: "ContextMenu",
    Scroll: "ScrollLock",
    MozPrintableKey: "Unidentified"
  }, $c = {
    8: "Backspace",
    9: "Tab",
    12: "Clear",
    13: "Enter",
    16: "Shift",
    17: "Control",
    18: "Alt",
    19: "Pause",
    20: "CapsLock",
    27: "Escape",
    32: " ",
    33: "PageUp",
    34: "PageDown",
    35: "End",
    36: "Home",
    37: "ArrowLeft",
    38: "ArrowUp",
    39: "ArrowRight",
    40: "ArrowDown",
    45: "Insert",
    46: "Delete",
    112: "F1",
    113: "F2",
    114: "F3",
    115: "F4",
    116: "F5",
    117: "F6",
    118: "F7",
    119: "F8",
    120: "F9",
    121: "F10",
    122: "F11",
    123: "F12",
    144: "NumLock",
    145: "ScrollLock",
    224: "Meta"
  }, Wc = { Alt: "altKey", Control: "ctrlKey", Meta: "metaKey", Shift: "shiftKey" };
  function Bc(e) {
    var t = this.nativeEvent;
    return t.getModifierState ? t.getModifierState(e) : (e = Wc[e]) ? !!t[e] : !1;
  }
  function Vi() {
    return Bc;
  }
  var Hc = P({}, Vr, { key: function(e) {
    if (e.key) {
      var t = Uc[e.key] || e.key;
      if (t !== "Unidentified") return t;
    }
    return e.type === "keypress" ? (e = Tl(e), e === 13 ? "Enter" : String.fromCharCode(e)) : e.type === "keydown" || e.type === "keyup" ? $c[e.keyCode] || "Unidentified" : "";
  }, code: 0, location: 0, ctrlKey: 0, shiftKey: 0, altKey: 0, metaKey: 0, repeat: 0, locale: 0, getModifierState: Vi, charCode: function(e) {
    return e.type === "keypress" ? Tl(e) : 0;
  }, keyCode: function(e) {
    return e.type === "keydown" || e.type === "keyup" ? e.keyCode : 0;
  }, which: function(e) {
    return e.type === "keypress" ? Tl(e) : e.type === "keydown" || e.type === "keyup" ? e.keyCode : 0;
  } }), Vc = Nt(Hc), Qc = P({}, Ol, { pointerId: 0, width: 0, height: 0, pressure: 0, tangentialPressure: 0, tiltX: 0, tiltY: 0, twist: 0, pointerType: 0, isPrimary: 0 }), Au = Nt(Qc), Kc = P({}, Vr, { touches: 0, targetTouches: 0, changedTouches: 0, altKey: 0, metaKey: 0, ctrlKey: 0, shiftKey: 0, getModifierState: Vi }), Yc = Nt(Kc), Xc = P({}, sr, { propertyName: 0, elapsedTime: 0, pseudoElement: 0 }), Gc = Nt(Xc), Zc = P({}, Ol, {
    deltaX: function(e) {
      return "deltaX" in e ? e.deltaX : "wheelDeltaX" in e ? -e.wheelDeltaX : 0;
    },
    deltaY: function(e) {
      return "deltaY" in e ? e.deltaY : "wheelDeltaY" in e ? -e.wheelDeltaY : "wheelDelta" in e ? -e.wheelDelta : 0;
    },
    deltaZ: 0,
    deltaMode: 0
  }), qc = Nt(Zc), Jc = [9, 13, 27, 32], Qi = ee && "CompositionEvent" in window, Kr = null;
  ee && "documentMode" in document && (Kr = document.documentMode);
  var bc = ee && "TextEvent" in window && !Kr, Du = ee && (!Qi || Kr && 8 < Kr && 11 >= Kr), Uu = " ", $u = !1;
  function Wu(e, t) {
    switch (e) {
      case "keyup":
        return Jc.indexOf(t.keyCode) !== -1;
      case "keydown":
        return t.keyCode !== 229;
      case "keypress":
      case "mousedown":
      case "focusout":
        return !0;
      default:
        return !1;
    }
  }
  function Bu(e) {
    return e = e.detail, typeof e == "object" && "data" in e ? e.data : null;
  }
  var ar = !1;
  function ef(e, t) {
    switch (e) {
      case "compositionend":
        return Bu(t);
      case "keypress":
        return t.which !== 32 ? null : ($u = !0, Uu);
      case "textInput":
        return e = t.data, e === Uu && $u ? null : e;
      default:
        return null;
    }
  }
  function tf(e, t) {
    if (ar) return e === "compositionend" || !Qi && Wu(e, t) ? (e = Mu(), Rl = Ui = Nn = null, ar = !1, e) : null;
    switch (e) {
      case "paste":
        return null;
      case "keypress":
        if (!(t.ctrlKey || t.altKey || t.metaKey) || t.ctrlKey && t.altKey) {
          if (t.char && 1 < t.char.length) return t.char;
          if (t.which) return String.fromCharCode(t.which);
        }
        return null;
      case "compositionend":
        return Du && t.locale !== "ko" ? null : t.data;
      default:
        return null;
    }
  }
  var nf = { color: !0, date: !0, datetime: !0, "datetime-local": !0, email: !0, month: !0, number: !0, password: !0, range: !0, search: !0, tel: !0, text: !0, time: !0, url: !0, week: !0 };
  function Hu(e) {
    var t = e && e.nodeName && e.nodeName.toLowerCase();
    return t === "input" ? !!nf[e.type] : t === "textarea";
  }
  function Vu(e, t, n, r) {
    Mr(r), t = Ul(t, "onChange"), 0 < t.length && (n = new $i("onChange", "change", null, n, r), e.push({ event: n, listeners: t }));
  }
  var Yr = null, Xr = null;
  function rf(e) {
    ss(e, 0);
  }
  function Il(e) {
    var t = hr(e);
    if (ae(t)) return e;
  }
  function lf(e, t) {
    if (e === "change") return t;
  }
  var Qu = !1;
  if (ee) {
    var Ki;
    if (ee) {
      var Yi = "oninput" in document;
      if (!Yi) {
        var Ku = document.createElement("div");
        Ku.setAttribute("oninput", "return;"), Yi = typeof Ku.oninput == "function";
      }
      Ki = Yi;
    } else Ki = !1;
    Qu = Ki && (!document.documentMode || 9 < document.documentMode);
  }
  function Yu() {
    Yr && (Yr.detachEvent("onpropertychange", Xu), Xr = Yr = null);
  }
  function Xu(e) {
    if (e.propertyName === "value" && Il(Xr)) {
      var t = [];
      Vu(t, Xr, e, Dt(e)), b(rf, t);
    }
  }
  function of(e, t, n) {
    e === "focusin" ? (Yu(), Yr = t, Xr = n, Yr.attachEvent("onpropertychange", Xu)) : e === "focusout" && Yu();
  }
  function uf(e) {
    if (e === "selectionchange" || e === "keyup" || e === "keydown") return Il(Xr);
  }
  function sf(e, t) {
    if (e === "click") return Il(t);
  }
  function af(e, t) {
    if (e === "input" || e === "change") return Il(t);
  }
  function cf(e, t) {
    return e === t && (e !== 0 || 1 / e === 1 / t) || e !== e && t !== t;
  }
  var Wt = typeof Object.is == "function" ? Object.is : cf;
  function Gr(e, t) {
    if (Wt(e, t)) return !0;
    if (typeof e != "object" || e === null || typeof t != "object" || t === null) return !1;
    var n = Object.keys(e), r = Object.keys(t);
    if (n.length !== r.length) return !1;
    for (r = 0; r < n.length; r++) {
      var l = n[r];
      if (!I.call(t, l) || !Wt(e[l], t[l])) return !1;
    }
    return !0;
  }
  function Gu(e) {
    for (; e && e.firstChild; ) e = e.firstChild;
    return e;
  }
  function Zu(e, t) {
    var n = Gu(e);
    e = 0;
    for (var r; n; ) {
      if (n.nodeType === 3) {
        if (r = e + n.textContent.length, e <= t && r >= t) return { node: n, offset: t - e };
        e = r;
      }
      e: {
        for (; n; ) {
          if (n.nextSibling) {
            n = n.nextSibling;
            break e;
          }
          n = n.parentNode;
        }
        n = void 0;
      }
      n = Gu(n);
    }
  }
  function qu(e, t) {
    return e && t ? e === t ? !0 : e && e.nodeType === 3 ? !1 : t && t.nodeType === 3 ? qu(e, t.parentNode) : "contains" in e ? e.contains(t) : e.compareDocumentPosition ? !!(e.compareDocumentPosition(t) & 16) : !1 : !1;
  }
  function Ju() {
    for (var e = window, t = ke(); t instanceof e.HTMLIFrameElement; ) {
      try {
        var n = typeof t.contentWindow.location.href == "string";
      } catch {
        n = !1;
      }
      if (n) e = t.contentWindow;
      else break;
      t = ke(e.document);
    }
    return t;
  }
  function Xi(e) {
    var t = e && e.nodeName && e.nodeName.toLowerCase();
    return t && (t === "input" && (e.type === "text" || e.type === "search" || e.type === "tel" || e.type === "url" || e.type === "password") || t === "textarea" || e.contentEditable === "true");
  }
  function ff(e) {
    var t = Ju(), n = e.focusedElem, r = e.selectionRange;
    if (t !== n && n && n.ownerDocument && qu(n.ownerDocument.documentElement, n)) {
      if (r !== null && Xi(n)) {
        if (t = r.start, e = r.end, e === void 0 && (e = t), "selectionStart" in n) n.selectionStart = t, n.selectionEnd = Math.min(e, n.value.length);
        else if (e = (t = n.ownerDocument || document) && t.defaultView || window, e.getSelection) {
          e = e.getSelection();
          var l = n.textContent.length, i = Math.min(r.start, l);
          r = r.end === void 0 ? i : Math.min(r.end, l), !e.extend && i > r && (l = r, r = i, i = l), l = Zu(n, i);
          var o = Zu(
            n,
            r
          );
          l && o && (e.rangeCount !== 1 || e.anchorNode !== l.node || e.anchorOffset !== l.offset || e.focusNode !== o.node || e.focusOffset !== o.offset) && (t = t.createRange(), t.setStart(l.node, l.offset), e.removeAllRanges(), i > r ? (e.addRange(t), e.extend(o.node, o.offset)) : (t.setEnd(o.node, o.offset), e.addRange(t)));
        }
      }
      for (t = [], e = n; e = e.parentNode; ) e.nodeType === 1 && t.push({ element: e, left: e.scrollLeft, top: e.scrollTop });
      for (typeof n.focus == "function" && n.focus(), n = 0; n < t.length; n++) e = t[n], e.element.scrollLeft = e.left, e.element.scrollTop = e.top;
    }
  }
  var df = ee && "documentMode" in document && 11 >= document.documentMode, cr = null, Gi = null, Zr = null, Zi = !1;
  function bu(e, t, n) {
    var r = n.window === n ? n.document : n.nodeType === 9 ? n : n.ownerDocument;
    Zi || cr == null || cr !== ke(r) || (r = cr, "selectionStart" in r && Xi(r) ? r = { start: r.selectionStart, end: r.selectionEnd } : (r = (r.ownerDocument && r.ownerDocument.defaultView || window).getSelection(), r = { anchorNode: r.anchorNode, anchorOffset: r.anchorOffset, focusNode: r.focusNode, focusOffset: r.focusOffset }), Zr && Gr(Zr, r) || (Zr = r, r = Ul(Gi, "onSelect"), 0 < r.length && (t = new $i("onSelect", "select", null, t, n), e.push({ event: t, listeners: r }), t.target = cr)));
  }
  function Fl(e, t) {
    var n = {};
    return n[e.toLowerCase()] = t.toLowerCase(), n["Webkit" + e] = "webkit" + t, n["Moz" + e] = "moz" + t, n;
  }
  var fr = { animationend: Fl("Animation", "AnimationEnd"), animationiteration: Fl("Animation", "AnimationIteration"), animationstart: Fl("Animation", "AnimationStart"), transitionend: Fl("Transition", "TransitionEnd") }, qi = {}, es = {};
  ee && (es = document.createElement("div").style, "AnimationEvent" in window || (delete fr.animationend.animation, delete fr.animationiteration.animation, delete fr.animationstart.animation), "TransitionEvent" in window || delete fr.transitionend.transition);
  function Al(e) {
    if (qi[e]) return qi[e];
    if (!fr[e]) return e;
    var t = fr[e], n;
    for (n in t) if (t.hasOwnProperty(n) && n in es) return qi[e] = t[n];
    return e;
  }
  var ts = Al("animationend"), ns = Al("animationiteration"), rs = Al("animationstart"), ls = Al("transitionend"), is = /* @__PURE__ */ new Map(), os = "abort auxClick cancel canPlay canPlayThrough click close contextMenu copy cut drag dragEnd dragEnter dragExit dragLeave dragOver dragStart drop durationChange emptied encrypted ended error gotPointerCapture input invalid keyDown keyPress keyUp load loadedData loadedMetadata loadStart lostPointerCapture mouseDown mouseMove mouseOut mouseOver mouseUp paste pause play playing pointerCancel pointerDown pointerMove pointerOut pointerOver pointerUp progress rateChange reset resize seeked seeking stalled submit suspend timeUpdate touchCancel touchEnd touchStart volumeChange scroll toggle touchMove waiting wheel".split(" ");
  function jn(e, t) {
    is.set(e, t), C(t, [e]);
  }
  for (var Ji = 0; Ji < os.length; Ji++) {
    var bi = os[Ji], pf = bi.toLowerCase(), hf = bi[0].toUpperCase() + bi.slice(1);
    jn(pf, "on" + hf);
  }
  jn(ts, "onAnimationEnd"), jn(ns, "onAnimationIteration"), jn(rs, "onAnimationStart"), jn("dblclick", "onDoubleClick"), jn("focusin", "onFocus"), jn("focusout", "onBlur"), jn(ls, "onTransitionEnd"), V("onMouseEnter", ["mouseout", "mouseover"]), V("onMouseLeave", ["mouseout", "mouseover"]), V("onPointerEnter", ["pointerout", "pointerover"]), V("onPointerLeave", ["pointerout", "pointerover"]), C("onChange", "change click focusin focusout input keydown keyup selectionchange".split(" ")), C("onSelect", "focusout contextmenu dragend focusin keydown keyup mousedown mouseup selectionchange".split(" ")), C("onBeforeInput", ["compositionend", "keypress", "textInput", "paste"]), C("onCompositionEnd", "compositionend focusout keydown keypress keyup mousedown".split(" ")), C("onCompositionStart", "compositionstart focusout keydown keypress keyup mousedown".split(" ")), C("onCompositionUpdate", "compositionupdate focusout keydown keypress keyup mousedown".split(" "));
  var qr = "abort canplay canplaythrough durationchange emptied encrypted ended error loadeddata loadedmetadata loadstart pause play playing progress ratechange resize seeked seeking stalled suspend timeupdate volumechange waiting".split(" "), mf = new Set("cancel close invalid load scroll toggle".split(" ").concat(qr));
  function us(e, t, n) {
    var r = e.type || "unknown-event";
    e.currentTarget = n, lr(r, t, void 0, e), e.currentTarget = null;
  }
  function ss(e, t) {
    t = (t & 4) !== 0;
    for (var n = 0; n < e.length; n++) {
      var r = e[n], l = r.event;
      r = r.listeners;
      e: {
        var i = void 0;
        if (t) for (var o = r.length - 1; 0 <= o; o--) {
          var s = r[o], a = s.instance, g = s.currentTarget;
          if (s = s.listener, a !== i && l.isPropagationStopped()) break e;
          us(l, s, g), i = a;
        }
        else for (o = 0; o < r.length; o++) {
          if (s = r[o], a = s.instance, g = s.currentTarget, s = s.listener, a !== i && l.isPropagationStopped()) break e;
          us(l, s, g), i = a;
        }
      }
    }
    if (Ge) throw e = Zt, Ge = !1, Zt = null, e;
  }
  function Le(e, t) {
    var n = t[uo];
    n === void 0 && (n = t[uo] = /* @__PURE__ */ new Set());
    var r = e + "__bubble";
    n.has(r) || (as(t, e, 2, !1), n.add(r));
  }
  function eo(e, t, n) {
    var r = 0;
    t && (r |= 4), as(n, e, r, t);
  }
  var Dl = "_reactListening" + Math.random().toString(36).slice(2);
  function Jr(e) {
    if (!e[Dl]) {
      e[Dl] = !0, N.forEach(function(n) {
        n !== "selectionchange" && (mf.has(n) || eo(n, !1, e), eo(n, !0, e));
      });
      var t = e.nodeType === 9 ? e : e.ownerDocument;
      t === null || t[Dl] || (t[Dl] = !0, eo("selectionchange", !1, t));
    }
  }
  function as(e, t, n, r) {
    switch (Tu(t)) {
      case 1:
        var l = zc;
        break;
      case 4:
        l = Lc;
        break;
      default:
        l = Ai;
    }
    n = l.bind(null, t, n, e), l = void 0, !Se || t !== "touchstart" && t !== "touchmove" && t !== "wheel" || (l = !0), r ? l !== void 0 ? e.addEventListener(t, n, { capture: !0, passive: l }) : e.addEventListener(t, n, !0) : l !== void 0 ? e.addEventListener(t, n, { passive: l }) : e.addEventListener(t, n, !1);
  }
  function to(e, t, n, r, l) {
    var i = r;
    if ((t & 1) === 0 && (t & 2) === 0 && r !== null) e: for (; ; ) {
      if (r === null) return;
      var o = r.tag;
      if (o === 3 || o === 4) {
        var s = r.stateNode.containerInfo;
        if (s === l || s.nodeType === 8 && s.parentNode === l) break;
        if (o === 4) for (o = r.return; o !== null; ) {
          var a = o.tag;
          if ((a === 3 || a === 4) && (a = o.stateNode.containerInfo, a === l || a.nodeType === 8 && a.parentNode === l)) return;
          o = o.return;
        }
        for (; s !== null; ) {
          if (o = Hn(s), o === null) return;
          if (a = o.tag, a === 5 || a === 6) {
            r = i = o;
            continue e;
          }
          s = s.parentNode;
        }
      }
      r = r.return;
    }
    b(function() {
      var g = i, E = Dt(n), _ = [];
      e: {
        var S = is.get(e);
        if (S !== void 0) {
          var M = $i, A = e;
          switch (e) {
            case "keypress":
              if (Tl(n) === 0) break e;
            case "keydown":
            case "keyup":
              M = Vc;
              break;
            case "focusin":
              A = "focus", M = Hi;
              break;
            case "focusout":
              A = "blur", M = Hi;
              break;
            case "beforeblur":
            case "afterblur":
              M = Hi;
              break;
            case "click":
              if (n.button === 2) break e;
            case "auxclick":
            case "dblclick":
            case "mousedown":
            case "mousemove":
            case "mouseup":
            case "mouseout":
            case "mouseover":
            case "contextmenu":
              M = Iu;
              break;
            case "drag":
            case "dragend":
            case "dragenter":
            case "dragexit":
            case "dragleave":
            case "dragover":
            case "dragstart":
            case "drop":
              M = Tc;
              break;
            case "touchcancel":
            case "touchend":
            case "touchmove":
            case "touchstart":
              M = Yc;
              break;
            case ts:
            case ns:
            case rs:
              M = Ic;
              break;
            case ls:
              M = Gc;
              break;
            case "scroll":
              M = Pc;
              break;
            case "wheel":
              M = qc;
              break;
            case "copy":
            case "cut":
            case "paste":
              M = Ac;
              break;
            case "gotpointercapture":
            case "lostpointercapture":
            case "pointercancel":
            case "pointerdown":
            case "pointermove":
            case "pointerout":
            case "pointerover":
            case "pointerup":
              M = Au;
          }
          var U = (t & 4) !== 0, We = !U && e === "scroll", h = U ? S !== null ? S + "Capture" : null : S;
          U = [];
          for (var p = g, v; p !== null; ) {
            v = p;
            var z = v.stateNode;
            if (v.tag === 5 && z !== null && (v = z, h !== null && (z = Re(p, h), z != null && U.push(br(p, z, v)))), We) break;
            p = p.return;
          }
          0 < U.length && (S = new M(S, A, null, n, E), _.push({ event: S, listeners: U }));
        }
      }
      if ((t & 7) === 0) {
        e: {
          if (S = e === "mouseover" || e === "pointerover", M = e === "mouseout" || e === "pointerout", S && n !== Gt && (A = n.relatedTarget || n.fromElement) && (Hn(A) || A[fn])) break e;
          if ((M || S) && (S = E.window === E ? E : (S = E.ownerDocument) ? S.defaultView || S.parentWindow : window, M ? (A = n.relatedTarget || n.toElement, M = g, A = A ? Hn(A) : null, A !== null && (We = mt(A), A !== We || A.tag !== 5 && A.tag !== 6) && (A = null)) : (M = null, A = g), M !== A)) {
            if (U = Iu, z = "onMouseLeave", h = "onMouseEnter", p = "mouse", (e === "pointerout" || e === "pointerover") && (U = Au, z = "onPointerLeave", h = "onPointerEnter", p = "pointer"), We = M == null ? S : hr(M), v = A == null ? S : hr(A), S = new U(z, p + "leave", M, n, E), S.target = We, S.relatedTarget = v, z = null, Hn(E) === g && (U = new U(h, p + "enter", A, n, E), U.target = v, U.relatedTarget = We, z = U), We = z, M && A) t: {
              for (U = M, h = A, p = 0, v = U; v; v = dr(v)) p++;
              for (v = 0, z = h; z; z = dr(z)) v++;
              for (; 0 < p - v; ) U = dr(U), p--;
              for (; 0 < v - p; ) h = dr(h), v--;
              for (; p--; ) {
                if (U === h || h !== null && U === h.alternate) break t;
                U = dr(U), h = dr(h);
              }
              U = null;
            }
            else U = null;
            M !== null && cs(_, S, M, U, !1), A !== null && We !== null && cs(_, We, A, U, !0);
          }
        }
        e: {
          if (S = g ? hr(g) : window, M = S.nodeName && S.nodeName.toLowerCase(), M === "select" || M === "input" && S.type === "file") var B = lf;
          else if (Hu(S)) if (Qu) B = af;
          else {
            B = uf;
            var X = of;
          }
          else (M = S.nodeName) && M.toLowerCase() === "input" && (S.type === "checkbox" || S.type === "radio") && (B = sf);
          if (B && (B = B(e, g))) {
            Vu(_, B, n, E);
            break e;
          }
          X && X(e, S, g), e === "focusout" && (X = S._wrapperState) && X.controlled && S.type === "number" && _e(S, "number", S.value);
        }
        switch (X = g ? hr(g) : window, e) {
          case "focusin":
            (Hu(X) || X.contentEditable === "true") && (cr = X, Gi = g, Zr = null);
            break;
          case "focusout":
            Zr = Gi = cr = null;
            break;
          case "mousedown":
            Zi = !0;
            break;
          case "contextmenu":
          case "mouseup":
          case "dragend":
            Zi = !1, bu(_, n, E);
            break;
          case "selectionchange":
            if (df) break;
          case "keydown":
          case "keyup":
            bu(_, n, E);
        }
        var G;
        if (Qi) e: {
          switch (e) {
            case "compositionstart":
              var J = "onCompositionStart";
              break e;
            case "compositionend":
              J = "onCompositionEnd";
              break e;
            case "compositionupdate":
              J = "onCompositionUpdate";
              break e;
          }
          J = void 0;
        }
        else ar ? Wu(e, n) && (J = "onCompositionEnd") : e === "keydown" && n.keyCode === 229 && (J = "onCompositionStart");
        J && (Du && n.locale !== "ko" && (ar || J !== "onCompositionStart" ? J === "onCompositionEnd" && ar && (G = Mu()) : (Nn = E, Ui = "value" in Nn ? Nn.value : Nn.textContent, ar = !0)), X = Ul(g, J), 0 < X.length && (J = new Fu(J, e, null, n, E), _.push({ event: J, listeners: X }), G ? J.data = G : (G = Bu(n), G !== null && (J.data = G)))), (G = bc ? ef(e, n) : tf(e, n)) && (g = Ul(g, "onBeforeInput"), 0 < g.length && (E = new Fu("onBeforeInput", "beforeinput", null, n, E), _.push({ event: E, listeners: g }), E.data = G));
      }
      ss(_, t);
    });
  }
  function br(e, t, n) {
    return { instance: e, listener: t, currentTarget: n };
  }
  function Ul(e, t) {
    for (var n = t + "Capture", r = []; e !== null; ) {
      var l = e, i = l.stateNode;
      l.tag === 5 && i !== null && (l = i, i = Re(e, n), i != null && r.unshift(br(e, i, l)), i = Re(e, t), i != null && r.push(br(e, i, l))), e = e.return;
    }
    return r;
  }
  function dr(e) {
    if (e === null) return null;
    do
      e = e.return;
    while (e && e.tag !== 5);
    return e || null;
  }
  function cs(e, t, n, r, l) {
    for (var i = t._reactName, o = []; n !== null && n !== r; ) {
      var s = n, a = s.alternate, g = s.stateNode;
      if (a !== null && a === r) break;
      s.tag === 5 && g !== null && (s = g, l ? (a = Re(n, i), a != null && o.unshift(br(n, a, s))) : l || (a = Re(n, i), a != null && o.push(br(n, a, s)))), n = n.return;
    }
    o.length !== 0 && e.push({ event: t, listeners: o });
  }
  var vf = /\r\n?/g, yf = /\u0000|\uFFFD/g;
  function fs(e) {
    return (typeof e == "string" ? e : "" + e).replace(vf, `
`).replace(yf, "");
  }
  function $l(e, t, n) {
    if (t = fs(t), fs(e) !== t && n) throw Error(f(425));
  }
  function Wl() {
  }
  var no = null, ro = null;
  function lo(e, t) {
    return e === "textarea" || e === "noscript" || typeof t.children == "string" || typeof t.children == "number" || typeof t.dangerouslySetInnerHTML == "object" && t.dangerouslySetInnerHTML !== null && t.dangerouslySetInnerHTML.__html != null;
  }
  var io = typeof setTimeout == "function" ? setTimeout : void 0, gf = typeof clearTimeout == "function" ? clearTimeout : void 0, ds = typeof Promise == "function" ? Promise : void 0, wf = typeof queueMicrotask == "function" ? queueMicrotask : typeof ds < "u" ? function(e) {
    return ds.resolve(null).then(e).catch(xf);
  } : io;
  function xf(e) {
    setTimeout(function() {
      throw e;
    });
  }
  function oo(e, t) {
    var n = t, r = 0;
    do {
      var l = n.nextSibling;
      if (e.removeChild(n), l && l.nodeType === 8) if (n = l.data, n === "/$") {
        if (r === 0) {
          e.removeChild(l), Hr(t);
          return;
        }
        r--;
      } else n !== "$" && n !== "$?" && n !== "$!" || r++;
      n = l;
    } while (n);
    Hr(t);
  }
  function zn(e) {
    for (; e != null; e = e.nextSibling) {
      var t = e.nodeType;
      if (t === 1 || t === 3) break;
      if (t === 8) {
        if (t = e.data, t === "$" || t === "$!" || t === "$?") break;
        if (t === "/$") return null;
      }
    }
    return e;
  }
  function ps(e) {
    e = e.previousSibling;
    for (var t = 0; e; ) {
      if (e.nodeType === 8) {
        var n = e.data;
        if (n === "$" || n === "$!" || n === "$?") {
          if (t === 0) return e;
          t--;
        } else n === "/$" && t++;
      }
      e = e.previousSibling;
    }
    return null;
  }
  var pr = Math.random().toString(36).slice(2), Jt = "__reactFiber$" + pr, el = "__reactProps$" + pr, fn = "__reactContainer$" + pr, uo = "__reactEvents$" + pr, kf = "__reactListeners$" + pr, Sf = "__reactHandles$" + pr;
  function Hn(e) {
    var t = e[Jt];
    if (t) return t;
    for (var n = e.parentNode; n; ) {
      if (t = n[fn] || n[Jt]) {
        if (n = t.alternate, t.child !== null || n !== null && n.child !== null) for (e = ps(e); e !== null; ) {
          if (n = e[Jt]) return n;
          e = ps(e);
        }
        return t;
      }
      e = n, n = e.parentNode;
    }
    return null;
  }
  function tl(e) {
    return e = e[Jt] || e[fn], !e || e.tag !== 5 && e.tag !== 6 && e.tag !== 13 && e.tag !== 3 ? null : e;
  }
  function hr(e) {
    if (e.tag === 5 || e.tag === 6) return e.stateNode;
    throw Error(f(33));
  }
  function Bl(e) {
    return e[el] || null;
  }
  var so = [], mr = -1;
  function Ln(e) {
    return { current: e };
  }
  function Pe(e) {
    0 > mr || (e.current = so[mr], so[mr] = null, mr--);
  }
  function Ce(e, t) {
    mr++, so[mr] = e.current, e.current = t;
  }
  var Pn = {}, it = Ln(Pn), yt = Ln(!1), Vn = Pn;
  function vr(e, t) {
    var n = e.type.contextTypes;
    if (!n) return Pn;
    var r = e.stateNode;
    if (r && r.__reactInternalMemoizedUnmaskedChildContext === t) return r.__reactInternalMemoizedMaskedChildContext;
    var l = {}, i;
    for (i in n) l[i] = t[i];
    return r && (e = e.stateNode, e.__reactInternalMemoizedUnmaskedChildContext = t, e.__reactInternalMemoizedMaskedChildContext = l), l;
  }
  function gt(e) {
    return e = e.childContextTypes, e != null;
  }
  function Hl() {
    Pe(yt), Pe(it);
  }
  function hs(e, t, n) {
    if (it.current !== Pn) throw Error(f(168));
    Ce(it, t), Ce(yt, n);
  }
  function ms(e, t, n) {
    var r = e.stateNode;
    if (t = t.childContextTypes, typeof r.getChildContext != "function") return n;
    r = r.getChildContext();
    for (var l in r) if (!(l in t)) throw Error(f(108, H(e) || "Unknown", l));
    return P({}, n, r);
  }
  function Vl(e) {
    return e = (e = e.stateNode) && e.__reactInternalMemoizedMergedChildContext || Pn, Vn = it.current, Ce(it, e), Ce(yt, yt.current), !0;
  }
  function vs(e, t, n) {
    var r = e.stateNode;
    if (!r) throw Error(f(169));
    n ? (e = ms(e, t, Vn), r.__reactInternalMemoizedMergedChildContext = e, Pe(yt), Pe(it), Ce(it, e)) : Pe(yt), Ce(yt, n);
  }
  var dn = null, Ql = !1, ao = !1;
  function ys(e) {
    dn === null ? dn = [e] : dn.push(e);
  }
  function Ef(e) {
    Ql = !0, ys(e);
  }
  function Rn() {
    if (!ao && dn !== null) {
      ao = !0;
      var e = 0, t = ge;
      try {
        var n = dn;
        for (ge = 1; e < n.length; e++) {
          var r = n[e];
          do
            r = r(!0);
          while (r !== null);
        }
        dn = null, Ql = !1;
      } catch (l) {
        throw dn !== null && (dn = dn.slice(e + 1)), Fr(Ri, Rn), l;
      } finally {
        ge = t, ao = !1;
      }
    }
    return null;
  }
  var yr = [], gr = 0, Kl = null, Yl = 0, Pt = [], Rt = 0, Qn = null, pn = 1, hn = "";
  function Kn(e, t) {
    yr[gr++] = Yl, yr[gr++] = Kl, Kl = e, Yl = t;
  }
  function gs(e, t, n) {
    Pt[Rt++] = pn, Pt[Rt++] = hn, Pt[Rt++] = Qn, Qn = e;
    var r = pn;
    e = hn;
    var l = 32 - $t(r) - 1;
    r &= ~(1 << l), n += 1;
    var i = 32 - $t(t) + l;
    if (30 < i) {
      var o = l - l % 5;
      i = (r & (1 << o) - 1).toString(32), r >>= o, l -= o, pn = 1 << 32 - $t(t) + l | n << l | r, hn = i + e;
    } else pn = 1 << i | n << l | r, hn = e;
  }
  function co(e) {
    e.return !== null && (Kn(e, 1), gs(e, 1, 0));
  }
  function fo(e) {
    for (; e === Kl; ) Kl = yr[--gr], yr[gr] = null, Yl = yr[--gr], yr[gr] = null;
    for (; e === Qn; ) Qn = Pt[--Rt], Pt[Rt] = null, hn = Pt[--Rt], Pt[Rt] = null, pn = Pt[--Rt], Pt[Rt] = null;
  }
  var jt = null, zt = null, Te = !1, Bt = null;
  function ws(e, t) {
    var n = It(5, null, null, 0);
    n.elementType = "DELETED", n.stateNode = t, n.return = e, t = e.deletions, t === null ? (e.deletions = [n], e.flags |= 16) : t.push(n);
  }
  function xs(e, t) {
    switch (e.tag) {
      case 5:
        var n = e.type;
        return t = t.nodeType !== 1 || n.toLowerCase() !== t.nodeName.toLowerCase() ? null : t, t !== null ? (e.stateNode = t, jt = e, zt = zn(t.firstChild), !0) : !1;
      case 6:
        return t = e.pendingProps === "" || t.nodeType !== 3 ? null : t, t !== null ? (e.stateNode = t, jt = e, zt = null, !0) : !1;
      case 13:
        return t = t.nodeType !== 8 ? null : t, t !== null ? (n = Qn !== null ? { id: pn, overflow: hn } : null, e.memoizedState = { dehydrated: t, treeContext: n, retryLane: 1073741824 }, n = It(18, null, null, 0), n.stateNode = t, n.return = e, e.child = n, jt = e, zt = null, !0) : !1;
      default:
        return !1;
    }
  }
  function po(e) {
    return (e.mode & 1) !== 0 && (e.flags & 128) === 0;
  }
  function ho(e) {
    if (Te) {
      var t = zt;
      if (t) {
        var n = t;
        if (!xs(e, t)) {
          if (po(e)) throw Error(f(418));
          t = zn(n.nextSibling);
          var r = jt;
          t && xs(e, t) ? ws(r, n) : (e.flags = e.flags & -4097 | 2, Te = !1, jt = e);
        }
      } else {
        if (po(e)) throw Error(f(418));
        e.flags = e.flags & -4097 | 2, Te = !1, jt = e;
      }
    }
  }
  function ks(e) {
    for (e = e.return; e !== null && e.tag !== 5 && e.tag !== 3 && e.tag !== 13; ) e = e.return;
    jt = e;
  }
  function Xl(e) {
    if (e !== jt) return !1;
    if (!Te) return ks(e), Te = !0, !1;
    var t;
    if ((t = e.tag !== 3) && !(t = e.tag !== 5) && (t = e.type, t = t !== "head" && t !== "body" && !lo(e.type, e.memoizedProps)), t && (t = zt)) {
      if (po(e)) throw Ss(), Error(f(418));
      for (; t; ) ws(e, t), t = zn(t.nextSibling);
    }
    if (ks(e), e.tag === 13) {
      if (e = e.memoizedState, e = e !== null ? e.dehydrated : null, !e) throw Error(f(317));
      e: {
        for (e = e.nextSibling, t = 0; e; ) {
          if (e.nodeType === 8) {
            var n = e.data;
            if (n === "/$") {
              if (t === 0) {
                zt = zn(e.nextSibling);
                break e;
              }
              t--;
            } else n !== "$" && n !== "$!" && n !== "$?" || t++;
          }
          e = e.nextSibling;
        }
        zt = null;
      }
    } else zt = jt ? zn(e.stateNode.nextSibling) : null;
    return !0;
  }
  function Ss() {
    for (var e = zt; e; ) e = zn(e.nextSibling);
  }
  function wr() {
    zt = jt = null, Te = !1;
  }
  function mo(e) {
    Bt === null ? Bt = [e] : Bt.push(e);
  }
  var _f = ve.ReactCurrentBatchConfig;
  function nl(e, t, n) {
    if (e = n.ref, e !== null && typeof e != "function" && typeof e != "object") {
      if (n._owner) {
        if (n = n._owner, n) {
          if (n.tag !== 1) throw Error(f(309));
          var r = n.stateNode;
        }
        if (!r) throw Error(f(147, e));
        var l = r, i = "" + e;
        return t !== null && t.ref !== null && typeof t.ref == "function" && t.ref._stringRef === i ? t.ref : (t = function(o) {
          var s = l.refs;
          o === null ? delete s[i] : s[i] = o;
        }, t._stringRef = i, t);
      }
      if (typeof e != "string") throw Error(f(284));
      if (!n._owner) throw Error(f(290, e));
    }
    return e;
  }
  function Gl(e, t) {
    throw e = Object.prototype.toString.call(t), Error(f(31, e === "[object Object]" ? "object with keys {" + Object.keys(t).join(", ") + "}" : e));
  }
  function Es(e) {
    var t = e._init;
    return t(e._payload);
  }
  function _s(e) {
    function t(h, p) {
      if (e) {
        var v = h.deletions;
        v === null ? (h.deletions = [p], h.flags |= 16) : v.push(p);
      }
    }
    function n(h, p) {
      if (!e) return null;
      for (; p !== null; ) t(h, p), p = p.sibling;
      return null;
    }
    function r(h, p) {
      for (h = /* @__PURE__ */ new Map(); p !== null; ) p.key !== null ? h.set(p.key, p) : h.set(p.index, p), p = p.sibling;
      return h;
    }
    function l(h, p) {
      return h = Un(h, p), h.index = 0, h.sibling = null, h;
    }
    function i(h, p, v) {
      return h.index = v, e ? (v = h.alternate, v !== null ? (v = v.index, v < p ? (h.flags |= 2, p) : v) : (h.flags |= 2, p)) : (h.flags |= 1048576, p);
    }
    function o(h) {
      return e && h.alternate === null && (h.flags |= 2), h;
    }
    function s(h, p, v, z) {
      return p === null || p.tag !== 6 ? (p = ou(v, h.mode, z), p.return = h, p) : (p = l(p, v), p.return = h, p);
    }
    function a(h, p, v, z) {
      var B = v.type;
      return B === je ? E(h, p, v.props.children, z, v.key) : p !== null && (p.elementType === B || typeof B == "object" && B !== null && B.$$typeof === ze && Es(B) === p.type) ? (z = l(p, v.props), z.ref = nl(h, p, v), z.return = h, z) : (z = wi(v.type, v.key, v.props, null, h.mode, z), z.ref = nl(h, p, v), z.return = h, z);
    }
    function g(h, p, v, z) {
      return p === null || p.tag !== 4 || p.stateNode.containerInfo !== v.containerInfo || p.stateNode.implementation !== v.implementation ? (p = uu(v, h.mode, z), p.return = h, p) : (p = l(p, v.children || []), p.return = h, p);
    }
    function E(h, p, v, z, B) {
      return p === null || p.tag !== 7 ? (p = er(v, h.mode, z, B), p.return = h, p) : (p = l(p, v), p.return = h, p);
    }
    function _(h, p, v) {
      if (typeof p == "string" && p !== "" || typeof p == "number") return p = ou("" + p, h.mode, v), p.return = h, p;
      if (typeof p == "object" && p !== null) {
        switch (p.$$typeof) {
          case Oe:
            return v = wi(p.type, p.key, p.props, null, h.mode, v), v.ref = nl(h, null, p), v.return = h, v;
          case Ie:
            return p = uu(p, h.mode, v), p.return = h, p;
          case ze:
            var z = p._init;
            return _(h, z(p._payload), v);
        }
        if (fe(p) || $(p)) return p = er(p, h.mode, v, null), p.return = h, p;
        Gl(h, p);
      }
      return null;
    }
    function S(h, p, v, z) {
      var B = p !== null ? p.key : null;
      if (typeof v == "string" && v !== "" || typeof v == "number") return B !== null ? null : s(h, p, "" + v, z);
      if (typeof v == "object" && v !== null) {
        switch (v.$$typeof) {
          case Oe:
            return v.key === B ? a(h, p, v, z) : null;
          case Ie:
            return v.key === B ? g(h, p, v, z) : null;
          case ze:
            return B = v._init, S(
              h,
              p,
              B(v._payload),
              z
            );
        }
        if (fe(v) || $(v)) return B !== null ? null : E(h, p, v, z, null);
        Gl(h, v);
      }
      return null;
    }
    function M(h, p, v, z, B) {
      if (typeof z == "string" && z !== "" || typeof z == "number") return h = h.get(v) || null, s(p, h, "" + z, B);
      if (typeof z == "object" && z !== null) {
        switch (z.$$typeof) {
          case Oe:
            return h = h.get(z.key === null ? v : z.key) || null, a(p, h, z, B);
          case Ie:
            return h = h.get(z.key === null ? v : z.key) || null, g(p, h, z, B);
          case ze:
            var X = z._init;
            return M(h, p, v, X(z._payload), B);
        }
        if (fe(z) || $(z)) return h = h.get(v) || null, E(p, h, z, B, null);
        Gl(p, z);
      }
      return null;
    }
    function A(h, p, v, z) {
      for (var B = null, X = null, G = p, J = p = 0, Je = null; G !== null && J < v.length; J++) {
        G.index > J ? (Je = G, G = null) : Je = G.sibling;
        var he = S(h, G, v[J], z);
        if (he === null) {
          G === null && (G = Je);
          break;
        }
        e && G && he.alternate === null && t(h, G), p = i(he, p, J), X === null ? B = he : X.sibling = he, X = he, G = Je;
      }
      if (J === v.length) return n(h, G), Te && Kn(h, J), B;
      if (G === null) {
        for (; J < v.length; J++) G = _(h, v[J], z), G !== null && (p = i(G, p, J), X === null ? B = G : X.sibling = G, X = G);
        return Te && Kn(h, J), B;
      }
      for (G = r(h, G); J < v.length; J++) Je = M(G, h, J, v[J], z), Je !== null && (e && Je.alternate !== null && G.delete(Je.key === null ? J : Je.key), p = i(Je, p, J), X === null ? B = Je : X.sibling = Je, X = Je);
      return e && G.forEach(function($n) {
        return t(h, $n);
      }), Te && Kn(h, J), B;
    }
    function U(h, p, v, z) {
      var B = $(v);
      if (typeof B != "function") throw Error(f(150));
      if (v = B.call(v), v == null) throw Error(f(151));
      for (var X = B = null, G = p, J = p = 0, Je = null, he = v.next(); G !== null && !he.done; J++, he = v.next()) {
        G.index > J ? (Je = G, G = null) : Je = G.sibling;
        var $n = S(h, G, he.value, z);
        if ($n === null) {
          G === null && (G = Je);
          break;
        }
        e && G && $n.alternate === null && t(h, G), p = i($n, p, J), X === null ? B = $n : X.sibling = $n, X = $n, G = Je;
      }
      if (he.done) return n(
        h,
        G
      ), Te && Kn(h, J), B;
      if (G === null) {
        for (; !he.done; J++, he = v.next()) he = _(h, he.value, z), he !== null && (p = i(he, p, J), X === null ? B = he : X.sibling = he, X = he);
        return Te && Kn(h, J), B;
      }
      for (G = r(h, G); !he.done; J++, he = v.next()) he = M(G, h, J, he.value, z), he !== null && (e && he.alternate !== null && G.delete(he.key === null ? J : he.key), p = i(he, p, J), X === null ? B = he : X.sibling = he, X = he);
      return e && G.forEach(function(rd) {
        return t(h, rd);
      }), Te && Kn(h, J), B;
    }
    function We(h, p, v, z) {
      if (typeof v == "object" && v !== null && v.type === je && v.key === null && (v = v.props.children), typeof v == "object" && v !== null) {
        switch (v.$$typeof) {
          case Oe:
            e: {
              for (var B = v.key, X = p; X !== null; ) {
                if (X.key === B) {
                  if (B = v.type, B === je) {
                    if (X.tag === 7) {
                      n(h, X.sibling), p = l(X, v.props.children), p.return = h, h = p;
                      break e;
                    }
                  } else if (X.elementType === B || typeof B == "object" && B !== null && B.$$typeof === ze && Es(B) === X.type) {
                    n(h, X.sibling), p = l(X, v.props), p.ref = nl(h, X, v), p.return = h, h = p;
                    break e;
                  }
                  n(h, X);
                  break;
                } else t(h, X);
                X = X.sibling;
              }
              v.type === je ? (p = er(v.props.children, h.mode, z, v.key), p.return = h, h = p) : (z = wi(v.type, v.key, v.props, null, h.mode, z), z.ref = nl(h, p, v), z.return = h, h = z);
            }
            return o(h);
          case Ie:
            e: {
              for (X = v.key; p !== null; ) {
                if (p.key === X) if (p.tag === 4 && p.stateNode.containerInfo === v.containerInfo && p.stateNode.implementation === v.implementation) {
                  n(h, p.sibling), p = l(p, v.children || []), p.return = h, h = p;
                  break e;
                } else {
                  n(h, p);
                  break;
                }
                else t(h, p);
                p = p.sibling;
              }
              p = uu(v, h.mode, z), p.return = h, h = p;
            }
            return o(h);
          case ze:
            return X = v._init, We(h, p, X(v._payload), z);
        }
        if (fe(v)) return A(h, p, v, z);
        if ($(v)) return U(h, p, v, z);
        Gl(h, v);
      }
      return typeof v == "string" && v !== "" || typeof v == "number" ? (v = "" + v, p !== null && p.tag === 6 ? (n(h, p.sibling), p = l(p, v), p.return = h, h = p) : (n(h, p), p = ou(v, h.mode, z), p.return = h, h = p), o(h)) : n(h, p);
    }
    return We;
  }
  var xr = _s(!0), Cs = _s(!1), Zl = Ln(null), ql = null, kr = null, vo = null;
  function yo() {
    vo = kr = ql = null;
  }
  function go(e) {
    var t = Zl.current;
    Pe(Zl), e._currentValue = t;
  }
  function wo(e, t, n) {
    for (; e !== null; ) {
      var r = e.alternate;
      if ((e.childLanes & t) !== t ? (e.childLanes |= t, r !== null && (r.childLanes |= t)) : r !== null && (r.childLanes & t) !== t && (r.childLanes |= t), e === n) break;
      e = e.return;
    }
  }
  function Sr(e, t) {
    ql = e, vo = kr = null, e = e.dependencies, e !== null && e.firstContext !== null && ((e.lanes & t) !== 0 && (wt = !0), e.firstContext = null);
  }
  function Tt(e) {
    var t = e._currentValue;
    if (vo !== e) if (e = { context: e, memoizedValue: t, next: null }, kr === null) {
      if (ql === null) throw Error(f(308));
      kr = e, ql.dependencies = { lanes: 0, firstContext: e };
    } else kr = kr.next = e;
    return t;
  }
  var Yn = null;
  function xo(e) {
    Yn === null ? Yn = [e] : Yn.push(e);
  }
  function Ns(e, t, n, r) {
    var l = t.interleaved;
    return l === null ? (n.next = n, xo(t)) : (n.next = l.next, l.next = n), t.interleaved = n, mn(e, r);
  }
  function mn(e, t) {
    e.lanes |= t;
    var n = e.alternate;
    for (n !== null && (n.lanes |= t), n = e, e = e.return; e !== null; ) e.childLanes |= t, n = e.alternate, n !== null && (n.childLanes |= t), n = e, e = e.return;
    return n.tag === 3 ? n.stateNode : null;
  }
  var Tn = !1;
  function ko(e) {
    e.updateQueue = { baseState: e.memoizedState, firstBaseUpdate: null, lastBaseUpdate: null, shared: { pending: null, interleaved: null, lanes: 0 }, effects: null };
  }
  function js(e, t) {
    e = e.updateQueue, t.updateQueue === e && (t.updateQueue = { baseState: e.baseState, firstBaseUpdate: e.firstBaseUpdate, lastBaseUpdate: e.lastBaseUpdate, shared: e.shared, effects: e.effects });
  }
  function vn(e, t) {
    return { eventTime: e, lane: t, tag: 0, payload: null, callback: null, next: null };
  }
  function Mn(e, t, n) {
    var r = e.updateQueue;
    if (r === null) return null;
    if (r = r.shared, (pe & 2) !== 0) {
      var l = r.pending;
      return l === null ? t.next = t : (t.next = l.next, l.next = t), r.pending = t, mn(e, n);
    }
    return l = r.interleaved, l === null ? (t.next = t, xo(r)) : (t.next = l.next, l.next = t), r.interleaved = t, mn(e, n);
  }
  function Jl(e, t, n) {
    if (t = t.updateQueue, t !== null && (t = t.shared, (n & 4194240) !== 0)) {
      var r = t.lanes;
      r &= e.pendingLanes, n |= r, t.lanes = n, Oi(e, n);
    }
  }
  function zs(e, t) {
    var n = e.updateQueue, r = e.alternate;
    if (r !== null && (r = r.updateQueue, n === r)) {
      var l = null, i = null;
      if (n = n.firstBaseUpdate, n !== null) {
        do {
          var o = { eventTime: n.eventTime, lane: n.lane, tag: n.tag, payload: n.payload, callback: n.callback, next: null };
          i === null ? l = i = o : i = i.next = o, n = n.next;
        } while (n !== null);
        i === null ? l = i = t : i = i.next = t;
      } else l = i = t;
      n = { baseState: r.baseState, firstBaseUpdate: l, lastBaseUpdate: i, shared: r.shared, effects: r.effects }, e.updateQueue = n;
      return;
    }
    e = n.lastBaseUpdate, e === null ? n.firstBaseUpdate = t : e.next = t, n.lastBaseUpdate = t;
  }
  function bl(e, t, n, r) {
    var l = e.updateQueue;
    Tn = !1;
    var i = l.firstBaseUpdate, o = l.lastBaseUpdate, s = l.shared.pending;
    if (s !== null) {
      l.shared.pending = null;
      var a = s, g = a.next;
      a.next = null, o === null ? i = g : o.next = g, o = a;
      var E = e.alternate;
      E !== null && (E = E.updateQueue, s = E.lastBaseUpdate, s !== o && (s === null ? E.firstBaseUpdate = g : s.next = g, E.lastBaseUpdate = a));
    }
    if (i !== null) {
      var _ = l.baseState;
      o = 0, E = g = a = null, s = i;
      do {
        var S = s.lane, M = s.eventTime;
        if ((r & S) === S) {
          E !== null && (E = E.next = {
            eventTime: M,
            lane: 0,
            tag: s.tag,
            payload: s.payload,
            callback: s.callback,
            next: null
          });
          e: {
            var A = e, U = s;
            switch (S = t, M = n, U.tag) {
              case 1:
                if (A = U.payload, typeof A == "function") {
                  _ = A.call(M, _, S);
                  break e;
                }
                _ = A;
                break e;
              case 3:
                A.flags = A.flags & -65537 | 128;
              case 0:
                if (A = U.payload, S = typeof A == "function" ? A.call(M, _, S) : A, S == null) break e;
                _ = P({}, _, S);
                break e;
              case 2:
                Tn = !0;
            }
          }
          s.callback !== null && s.lane !== 0 && (e.flags |= 64, S = l.effects, S === null ? l.effects = [s] : S.push(s));
        } else M = { eventTime: M, lane: S, tag: s.tag, payload: s.payload, callback: s.callback, next: null }, E === null ? (g = E = M, a = _) : E = E.next = M, o |= S;
        if (s = s.next, s === null) {
          if (s = l.shared.pending, s === null) break;
          S = s, s = S.next, S.next = null, l.lastBaseUpdate = S, l.shared.pending = null;
        }
      } while (!0);
      if (E === null && (a = _), l.baseState = a, l.firstBaseUpdate = g, l.lastBaseUpdate = E, t = l.shared.interleaved, t !== null) {
        l = t;
        do
          o |= l.lane, l = l.next;
        while (l !== t);
      } else i === null && (l.shared.lanes = 0);
      Zn |= o, e.lanes = o, e.memoizedState = _;
    }
  }
  function Ls(e, t, n) {
    if (e = t.effects, t.effects = null, e !== null) for (t = 0; t < e.length; t++) {
      var r = e[t], l = r.callback;
      if (l !== null) {
        if (r.callback = null, r = n, typeof l != "function") throw Error(f(191, l));
        l.call(r);
      }
    }
  }
  var rl = {}, bt = Ln(rl), ll = Ln(rl), il = Ln(rl);
  function Xn(e) {
    if (e === rl) throw Error(f(174));
    return e;
  }
  function So(e, t) {
    switch (Ce(il, t), Ce(ll, e), Ce(bt, rl), e = t.nodeType, e) {
      case 9:
      case 11:
        t = (t = t.documentElement) ? t.namespaceURI : on(null, "");
        break;
      default:
        e = e === 8 ? t.parentNode : t, t = e.namespaceURI || null, e = e.tagName, t = on(t, e);
    }
    Pe(bt), Ce(bt, t);
  }
  function Er() {
    Pe(bt), Pe(ll), Pe(il);
  }
  function Ps(e) {
    Xn(il.current);
    var t = Xn(bt.current), n = on(t, e.type);
    t !== n && (Ce(ll, e), Ce(bt, n));
  }
  function Eo(e) {
    ll.current === e && (Pe(bt), Pe(ll));
  }
  var Fe = Ln(0);
  function ei(e) {
    for (var t = e; t !== null; ) {
      if (t.tag === 13) {
        var n = t.memoizedState;
        if (n !== null && (n = n.dehydrated, n === null || n.data === "$?" || n.data === "$!")) return t;
      } else if (t.tag === 19 && t.memoizedProps.revealOrder !== void 0) {
        if ((t.flags & 128) !== 0) return t;
      } else if (t.child !== null) {
        t.child.return = t, t = t.child;
        continue;
      }
      if (t === e) break;
      for (; t.sibling === null; ) {
        if (t.return === null || t.return === e) return null;
        t = t.return;
      }
      t.sibling.return = t.return, t = t.sibling;
    }
    return null;
  }
  var _o = [];
  function Co() {
    for (var e = 0; e < _o.length; e++) _o[e]._workInProgressVersionPrimary = null;
    _o.length = 0;
  }
  var ti = ve.ReactCurrentDispatcher, No = ve.ReactCurrentBatchConfig, Gn = 0, Ae = null, Qe = null, Ze = null, ni = !1, ol = !1, ul = 0, Cf = 0;
  function ot() {
    throw Error(f(321));
  }
  function jo(e, t) {
    if (t === null) return !1;
    for (var n = 0; n < t.length && n < e.length; n++) if (!Wt(e[n], t[n])) return !1;
    return !0;
  }
  function zo(e, t, n, r, l, i) {
    if (Gn = i, Ae = t, t.memoizedState = null, t.updateQueue = null, t.lanes = 0, ti.current = e === null || e.memoizedState === null ? Lf : Pf, e = n(r, l), ol) {
      i = 0;
      do {
        if (ol = !1, ul = 0, 25 <= i) throw Error(f(301));
        i += 1, Ze = Qe = null, t.updateQueue = null, ti.current = Rf, e = n(r, l);
      } while (ol);
    }
    if (ti.current = ii, t = Qe !== null && Qe.next !== null, Gn = 0, Ze = Qe = Ae = null, ni = !1, t) throw Error(f(300));
    return e;
  }
  function Lo() {
    var e = ul !== 0;
    return ul = 0, e;
  }
  function en() {
    var e = { memoizedState: null, baseState: null, baseQueue: null, queue: null, next: null };
    return Ze === null ? Ae.memoizedState = Ze = e : Ze = Ze.next = e, Ze;
  }
  function Mt() {
    if (Qe === null) {
      var e = Ae.alternate;
      e = e !== null ? e.memoizedState : null;
    } else e = Qe.next;
    var t = Ze === null ? Ae.memoizedState : Ze.next;
    if (t !== null) Ze = t, Qe = e;
    else {
      if (e === null) throw Error(f(310));
      Qe = e, e = { memoizedState: Qe.memoizedState, baseState: Qe.baseState, baseQueue: Qe.baseQueue, queue: Qe.queue, next: null }, Ze === null ? Ae.memoizedState = Ze = e : Ze = Ze.next = e;
    }
    return Ze;
  }
  function sl(e, t) {
    return typeof t == "function" ? t(e) : t;
  }
  function Po(e) {
    var t = Mt(), n = t.queue;
    if (n === null) throw Error(f(311));
    n.lastRenderedReducer = e;
    var r = Qe, l = r.baseQueue, i = n.pending;
    if (i !== null) {
      if (l !== null) {
        var o = l.next;
        l.next = i.next, i.next = o;
      }
      r.baseQueue = l = i, n.pending = null;
    }
    if (l !== null) {
      i = l.next, r = r.baseState;
      var s = o = null, a = null, g = i;
      do {
        var E = g.lane;
        if ((Gn & E) === E) a !== null && (a = a.next = { lane: 0, action: g.action, hasEagerState: g.hasEagerState, eagerState: g.eagerState, next: null }), r = g.hasEagerState ? g.eagerState : e(r, g.action);
        else {
          var _ = {
            lane: E,
            action: g.action,
            hasEagerState: g.hasEagerState,
            eagerState: g.eagerState,
            next: null
          };
          a === null ? (s = a = _, o = r) : a = a.next = _, Ae.lanes |= E, Zn |= E;
        }
        g = g.next;
      } while (g !== null && g !== i);
      a === null ? o = r : a.next = s, Wt(r, t.memoizedState) || (wt = !0), t.memoizedState = r, t.baseState = o, t.baseQueue = a, n.lastRenderedState = r;
    }
    if (e = n.interleaved, e !== null) {
      l = e;
      do
        i = l.lane, Ae.lanes |= i, Zn |= i, l = l.next;
      while (l !== e);
    } else l === null && (n.lanes = 0);
    return [t.memoizedState, n.dispatch];
  }
  function Ro(e) {
    var t = Mt(), n = t.queue;
    if (n === null) throw Error(f(311));
    n.lastRenderedReducer = e;
    var r = n.dispatch, l = n.pending, i = t.memoizedState;
    if (l !== null) {
      n.pending = null;
      var o = l = l.next;
      do
        i = e(i, o.action), o = o.next;
      while (o !== l);
      Wt(i, t.memoizedState) || (wt = !0), t.memoizedState = i, t.baseQueue === null && (t.baseState = i), n.lastRenderedState = i;
    }
    return [i, r];
  }
  function Rs() {
  }
  function Ts(e, t) {
    var n = Ae, r = Mt(), l = t(), i = !Wt(r.memoizedState, l);
    if (i && (r.memoizedState = l, wt = !0), r = r.queue, To(Is.bind(null, n, r, e), [e]), r.getSnapshot !== t || i || Ze !== null && Ze.memoizedState.tag & 1) {
      if (n.flags |= 2048, al(9, Os.bind(null, n, r, l, t), void 0, null), qe === null) throw Error(f(349));
      (Gn & 30) !== 0 || Ms(n, t, l);
    }
    return l;
  }
  function Ms(e, t, n) {
    e.flags |= 16384, e = { getSnapshot: t, value: n }, t = Ae.updateQueue, t === null ? (t = { lastEffect: null, stores: null }, Ae.updateQueue = t, t.stores = [e]) : (n = t.stores, n === null ? t.stores = [e] : n.push(e));
  }
  function Os(e, t, n, r) {
    t.value = n, t.getSnapshot = r, Fs(t) && As(e);
  }
  function Is(e, t, n) {
    return n(function() {
      Fs(t) && As(e);
    });
  }
  function Fs(e) {
    var t = e.getSnapshot;
    e = e.value;
    try {
      var n = t();
      return !Wt(e, n);
    } catch {
      return !0;
    }
  }
  function As(e) {
    var t = mn(e, 1);
    t !== null && Kt(t, e, 1, -1);
  }
  function Ds(e) {
    var t = en();
    return typeof e == "function" && (e = e()), t.memoizedState = t.baseState = e, e = { pending: null, interleaved: null, lanes: 0, dispatch: null, lastRenderedReducer: sl, lastRenderedState: e }, t.queue = e, e = e.dispatch = zf.bind(null, Ae, e), [t.memoizedState, e];
  }
  function al(e, t, n, r) {
    return e = { tag: e, create: t, destroy: n, deps: r, next: null }, t = Ae.updateQueue, t === null ? (t = { lastEffect: null, stores: null }, Ae.updateQueue = t, t.lastEffect = e.next = e) : (n = t.lastEffect, n === null ? t.lastEffect = e.next = e : (r = n.next, n.next = e, e.next = r, t.lastEffect = e)), e;
  }
  function Us() {
    return Mt().memoizedState;
  }
  function ri(e, t, n, r) {
    var l = en();
    Ae.flags |= e, l.memoizedState = al(1 | t, n, void 0, r === void 0 ? null : r);
  }
  function li(e, t, n, r) {
    var l = Mt();
    r = r === void 0 ? null : r;
    var i = void 0;
    if (Qe !== null) {
      var o = Qe.memoizedState;
      if (i = o.destroy, r !== null && jo(r, o.deps)) {
        l.memoizedState = al(t, n, i, r);
        return;
      }
    }
    Ae.flags |= e, l.memoizedState = al(1 | t, n, i, r);
  }
  function $s(e, t) {
    return ri(8390656, 8, e, t);
  }
  function To(e, t) {
    return li(2048, 8, e, t);
  }
  function Ws(e, t) {
    return li(4, 2, e, t);
  }
  function Bs(e, t) {
    return li(4, 4, e, t);
  }
  function Hs(e, t) {
    if (typeof t == "function") return e = e(), t(e), function() {
      t(null);
    };
    if (t != null) return e = e(), t.current = e, function() {
      t.current = null;
    };
  }
  function Vs(e, t, n) {
    return n = n != null ? n.concat([e]) : null, li(4, 4, Hs.bind(null, t, e), n);
  }
  function Mo() {
  }
  function Qs(e, t) {
    var n = Mt();
    t = t === void 0 ? null : t;
    var r = n.memoizedState;
    return r !== null && t !== null && jo(t, r[1]) ? r[0] : (n.memoizedState = [e, t], e);
  }
  function Ks(e, t) {
    var n = Mt();
    t = t === void 0 ? null : t;
    var r = n.memoizedState;
    return r !== null && t !== null && jo(t, r[1]) ? r[0] : (e = e(), n.memoizedState = [e, t], e);
  }
  function Ys(e, t, n) {
    return (Gn & 21) === 0 ? (e.baseState && (e.baseState = !1, wt = !0), e.memoizedState = n) : (Wt(n, t) || (n = Eu(), Ae.lanes |= n, Zn |= n, e.baseState = !0), t);
  }
  function Nf(e, t) {
    var n = ge;
    ge = n !== 0 && 4 > n ? n : 4, e(!0);
    var r = No.transition;
    No.transition = {};
    try {
      e(!1), t();
    } finally {
      ge = n, No.transition = r;
    }
  }
  function Xs() {
    return Mt().memoizedState;
  }
  function jf(e, t, n) {
    var r = An(e);
    if (n = { lane: r, action: n, hasEagerState: !1, eagerState: null, next: null }, Gs(e)) Zs(t, n);
    else if (n = Ns(e, t, n, r), n !== null) {
      var l = ft();
      Kt(n, e, r, l), qs(n, t, r);
    }
  }
  function zf(e, t, n) {
    var r = An(e), l = { lane: r, action: n, hasEagerState: !1, eagerState: null, next: null };
    if (Gs(e)) Zs(t, l);
    else {
      var i = e.alternate;
      if (e.lanes === 0 && (i === null || i.lanes === 0) && (i = t.lastRenderedReducer, i !== null)) try {
        var o = t.lastRenderedState, s = i(o, n);
        if (l.hasEagerState = !0, l.eagerState = s, Wt(s, o)) {
          var a = t.interleaved;
          a === null ? (l.next = l, xo(t)) : (l.next = a.next, a.next = l), t.interleaved = l;
          return;
        }
      } catch {
      } finally {
      }
      n = Ns(e, t, l, r), n !== null && (l = ft(), Kt(n, e, r, l), qs(n, t, r));
    }
  }
  function Gs(e) {
    var t = e.alternate;
    return e === Ae || t !== null && t === Ae;
  }
  function Zs(e, t) {
    ol = ni = !0;
    var n = e.pending;
    n === null ? t.next = t : (t.next = n.next, n.next = t), e.pending = t;
  }
  function qs(e, t, n) {
    if ((n & 4194240) !== 0) {
      var r = t.lanes;
      r &= e.pendingLanes, n |= r, t.lanes = n, Oi(e, n);
    }
  }
  var ii = { readContext: Tt, useCallback: ot, useContext: ot, useEffect: ot, useImperativeHandle: ot, useInsertionEffect: ot, useLayoutEffect: ot, useMemo: ot, useReducer: ot, useRef: ot, useState: ot, useDebugValue: ot, useDeferredValue: ot, useTransition: ot, useMutableSource: ot, useSyncExternalStore: ot, useId: ot, unstable_isNewReconciler: !1 }, Lf = { readContext: Tt, useCallback: function(e, t) {
    return en().memoizedState = [e, t === void 0 ? null : t], e;
  }, useContext: Tt, useEffect: $s, useImperativeHandle: function(e, t, n) {
    return n = n != null ? n.concat([e]) : null, ri(
      4194308,
      4,
      Hs.bind(null, t, e),
      n
    );
  }, useLayoutEffect: function(e, t) {
    return ri(4194308, 4, e, t);
  }, useInsertionEffect: function(e, t) {
    return ri(4, 2, e, t);
  }, useMemo: function(e, t) {
    var n = en();
    return t = t === void 0 ? null : t, e = e(), n.memoizedState = [e, t], e;
  }, useReducer: function(e, t, n) {
    var r = en();
    return t = n !== void 0 ? n(t) : t, r.memoizedState = r.baseState = t, e = { pending: null, interleaved: null, lanes: 0, dispatch: null, lastRenderedReducer: e, lastRenderedState: t }, r.queue = e, e = e.dispatch = jf.bind(null, Ae, e), [r.memoizedState, e];
  }, useRef: function(e) {
    var t = en();
    return e = { current: e }, t.memoizedState = e;
  }, useState: Ds, useDebugValue: Mo, useDeferredValue: function(e) {
    return en().memoizedState = e;
  }, useTransition: function() {
    var e = Ds(!1), t = e[0];
    return e = Nf.bind(null, e[1]), en().memoizedState = e, [t, e];
  }, useMutableSource: function() {
  }, useSyncExternalStore: function(e, t, n) {
    var r = Ae, l = en();
    if (Te) {
      if (n === void 0) throw Error(f(407));
      n = n();
    } else {
      if (n = t(), qe === null) throw Error(f(349));
      (Gn & 30) !== 0 || Ms(r, t, n);
    }
    l.memoizedState = n;
    var i = { value: n, getSnapshot: t };
    return l.queue = i, $s(Is.bind(
      null,
      r,
      i,
      e
    ), [e]), r.flags |= 2048, al(9, Os.bind(null, r, i, n, t), void 0, null), n;
  }, useId: function() {
    var e = en(), t = qe.identifierPrefix;
    if (Te) {
      var n = hn, r = pn;
      n = (r & ~(1 << 32 - $t(r) - 1)).toString(32) + n, t = ":" + t + "R" + n, n = ul++, 0 < n && (t += "H" + n.toString(32)), t += ":";
    } else n = Cf++, t = ":" + t + "r" + n.toString(32) + ":";
    return e.memoizedState = t;
  }, unstable_isNewReconciler: !1 }, Pf = {
    readContext: Tt,
    useCallback: Qs,
    useContext: Tt,
    useEffect: To,
    useImperativeHandle: Vs,
    useInsertionEffect: Ws,
    useLayoutEffect: Bs,
    useMemo: Ks,
    useReducer: Po,
    useRef: Us,
    useState: function() {
      return Po(sl);
    },
    useDebugValue: Mo,
    useDeferredValue: function(e) {
      var t = Mt();
      return Ys(t, Qe.memoizedState, e);
    },
    useTransition: function() {
      var e = Po(sl)[0], t = Mt().memoizedState;
      return [e, t];
    },
    useMutableSource: Rs,
    useSyncExternalStore: Ts,
    useId: Xs,
    unstable_isNewReconciler: !1
  }, Rf = { readContext: Tt, useCallback: Qs, useContext: Tt, useEffect: To, useImperativeHandle: Vs, useInsertionEffect: Ws, useLayoutEffect: Bs, useMemo: Ks, useReducer: Ro, useRef: Us, useState: function() {
    return Ro(sl);
  }, useDebugValue: Mo, useDeferredValue: function(e) {
    var t = Mt();
    return Qe === null ? t.memoizedState = e : Ys(t, Qe.memoizedState, e);
  }, useTransition: function() {
    var e = Ro(sl)[0], t = Mt().memoizedState;
    return [e, t];
  }, useMutableSource: Rs, useSyncExternalStore: Ts, useId: Xs, unstable_isNewReconciler: !1 };
  function Ht(e, t) {
    if (e && e.defaultProps) {
      t = P({}, t), e = e.defaultProps;
      for (var n in e) t[n] === void 0 && (t[n] = e[n]);
      return t;
    }
    return t;
  }
  function Oo(e, t, n, r) {
    t = e.memoizedState, n = n(r, t), n = n == null ? t : P({}, t, n), e.memoizedState = n, e.lanes === 0 && (e.updateQueue.baseState = n);
  }
  var oi = { isMounted: function(e) {
    return (e = e._reactInternals) ? mt(e) === e : !1;
  }, enqueueSetState: function(e, t, n) {
    e = e._reactInternals;
    var r = ft(), l = An(e), i = vn(r, l);
    i.payload = t, n != null && (i.callback = n), t = Mn(e, i, l), t !== null && (Kt(t, e, l, r), Jl(t, e, l));
  }, enqueueReplaceState: function(e, t, n) {
    e = e._reactInternals;
    var r = ft(), l = An(e), i = vn(r, l);
    i.tag = 1, i.payload = t, n != null && (i.callback = n), t = Mn(e, i, l), t !== null && (Kt(t, e, l, r), Jl(t, e, l));
  }, enqueueForceUpdate: function(e, t) {
    e = e._reactInternals;
    var n = ft(), r = An(e), l = vn(n, r);
    l.tag = 2, t != null && (l.callback = t), t = Mn(e, l, r), t !== null && (Kt(t, e, r, n), Jl(t, e, r));
  } };
  function Js(e, t, n, r, l, i, o) {
    return e = e.stateNode, typeof e.shouldComponentUpdate == "function" ? e.shouldComponentUpdate(r, i, o) : t.prototype && t.prototype.isPureReactComponent ? !Gr(n, r) || !Gr(l, i) : !0;
  }
  function bs(e, t, n) {
    var r = !1, l = Pn, i = t.contextType;
    return typeof i == "object" && i !== null ? i = Tt(i) : (l = gt(t) ? Vn : it.current, r = t.contextTypes, i = (r = r != null) ? vr(e, l) : Pn), t = new t(n, i), e.memoizedState = t.state !== null && t.state !== void 0 ? t.state : null, t.updater = oi, e.stateNode = t, t._reactInternals = e, r && (e = e.stateNode, e.__reactInternalMemoizedUnmaskedChildContext = l, e.__reactInternalMemoizedMaskedChildContext = i), t;
  }
  function ea(e, t, n, r) {
    e = t.state, typeof t.componentWillReceiveProps == "function" && t.componentWillReceiveProps(n, r), typeof t.UNSAFE_componentWillReceiveProps == "function" && t.UNSAFE_componentWillReceiveProps(n, r), t.state !== e && oi.enqueueReplaceState(t, t.state, null);
  }
  function Io(e, t, n, r) {
    var l = e.stateNode;
    l.props = n, l.state = e.memoizedState, l.refs = {}, ko(e);
    var i = t.contextType;
    typeof i == "object" && i !== null ? l.context = Tt(i) : (i = gt(t) ? Vn : it.current, l.context = vr(e, i)), l.state = e.memoizedState, i = t.getDerivedStateFromProps, typeof i == "function" && (Oo(e, t, i, n), l.state = e.memoizedState), typeof t.getDerivedStateFromProps == "function" || typeof l.getSnapshotBeforeUpdate == "function" || typeof l.UNSAFE_componentWillMount != "function" && typeof l.componentWillMount != "function" || (t = l.state, typeof l.componentWillMount == "function" && l.componentWillMount(), typeof l.UNSAFE_componentWillMount == "function" && l.UNSAFE_componentWillMount(), t !== l.state && oi.enqueueReplaceState(l, l.state, null), bl(e, n, l, r), l.state = e.memoizedState), typeof l.componentDidMount == "function" && (e.flags |= 4194308);
  }
  function _r(e, t) {
    try {
      var n = "", r = t;
      do
        n += k(r), r = r.return;
      while (r);
      var l = n;
    } catch (i) {
      l = `
Error generating stack: ` + i.message + `
` + i.stack;
    }
    return { value: e, source: t, stack: l, digest: null };
  }
  function Fo(e, t, n) {
    return { value: e, source: null, stack: n ?? null, digest: t ?? null };
  }
  function Ao(e, t) {
    try {
      console.error(t.value);
    } catch (n) {
      setTimeout(function() {
        throw n;
      });
    }
  }
  var Tf = typeof WeakMap == "function" ? WeakMap : Map;
  function ta(e, t, n) {
    n = vn(-1, n), n.tag = 3, n.payload = { element: null };
    var r = t.value;
    return n.callback = function() {
      pi || (pi = !0, Jo = r), Ao(e, t);
    }, n;
  }
  function na(e, t, n) {
    n = vn(-1, n), n.tag = 3;
    var r = e.type.getDerivedStateFromError;
    if (typeof r == "function") {
      var l = t.value;
      n.payload = function() {
        return r(l);
      }, n.callback = function() {
        Ao(e, t);
      };
    }
    var i = e.stateNode;
    return i !== null && typeof i.componentDidCatch == "function" && (n.callback = function() {
      Ao(e, t), typeof r != "function" && (In === null ? In = /* @__PURE__ */ new Set([this]) : In.add(this));
      var o = t.stack;
      this.componentDidCatch(t.value, { componentStack: o !== null ? o : "" });
    }), n;
  }
  function ra(e, t, n) {
    var r = e.pingCache;
    if (r === null) {
      r = e.pingCache = new Tf();
      var l = /* @__PURE__ */ new Set();
      r.set(t, l);
    } else l = r.get(t), l === void 0 && (l = /* @__PURE__ */ new Set(), r.set(t, l));
    l.has(n) || (l.add(n), e = Kf.bind(null, e, t, n), t.then(e, e));
  }
  function la(e) {
    do {
      var t;
      if ((t = e.tag === 13) && (t = e.memoizedState, t = t !== null ? t.dehydrated !== null : !0), t) return e;
      e = e.return;
    } while (e !== null);
    return null;
  }
  function ia(e, t, n, r, l) {
    return (e.mode & 1) === 0 ? (e === t ? e.flags |= 65536 : (e.flags |= 128, n.flags |= 131072, n.flags &= -52805, n.tag === 1 && (n.alternate === null ? n.tag = 17 : (t = vn(-1, 1), t.tag = 2, Mn(n, t, 1))), n.lanes |= 1), e) : (e.flags |= 65536, e.lanes = l, e);
  }
  var Mf = ve.ReactCurrentOwner, wt = !1;
  function ct(e, t, n, r) {
    t.child = e === null ? Cs(t, null, n, r) : xr(t, e.child, n, r);
  }
  function oa(e, t, n, r, l) {
    n = n.render;
    var i = t.ref;
    return Sr(t, l), r = zo(e, t, n, r, i, l), n = Lo(), e !== null && !wt ? (t.updateQueue = e.updateQueue, t.flags &= -2053, e.lanes &= ~l, yn(e, t, l)) : (Te && n && co(t), t.flags |= 1, ct(e, t, r, l), t.child);
  }
  function ua(e, t, n, r, l) {
    if (e === null) {
      var i = n.type;
      return typeof i == "function" && !iu(i) && i.defaultProps === void 0 && n.compare === null && n.defaultProps === void 0 ? (t.tag = 15, t.type = i, sa(e, t, i, r, l)) : (e = wi(n.type, null, r, t, t.mode, l), e.ref = t.ref, e.return = t, t.child = e);
    }
    if (i = e.child, (e.lanes & l) === 0) {
      var o = i.memoizedProps;
      if (n = n.compare, n = n !== null ? n : Gr, n(o, r) && e.ref === t.ref) return yn(e, t, l);
    }
    return t.flags |= 1, e = Un(i, r), e.ref = t.ref, e.return = t, t.child = e;
  }
  function sa(e, t, n, r, l) {
    if (e !== null) {
      var i = e.memoizedProps;
      if (Gr(i, r) && e.ref === t.ref) if (wt = !1, t.pendingProps = r = i, (e.lanes & l) !== 0) (e.flags & 131072) !== 0 && (wt = !0);
      else return t.lanes = e.lanes, yn(e, t, l);
    }
    return Do(e, t, n, r, l);
  }
  function aa(e, t, n) {
    var r = t.pendingProps, l = r.children, i = e !== null ? e.memoizedState : null;
    if (r.mode === "hidden") if ((t.mode & 1) === 0) t.memoizedState = { baseLanes: 0, cachePool: null, transitions: null }, Ce(Nr, Lt), Lt |= n;
    else {
      if ((n & 1073741824) === 0) return e = i !== null ? i.baseLanes | n : n, t.lanes = t.childLanes = 1073741824, t.memoizedState = { baseLanes: e, cachePool: null, transitions: null }, t.updateQueue = null, Ce(Nr, Lt), Lt |= e, null;
      t.memoizedState = { baseLanes: 0, cachePool: null, transitions: null }, r = i !== null ? i.baseLanes : n, Ce(Nr, Lt), Lt |= r;
    }
    else i !== null ? (r = i.baseLanes | n, t.memoizedState = null) : r = n, Ce(Nr, Lt), Lt |= r;
    return ct(e, t, l, n), t.child;
  }
  function ca(e, t) {
    var n = t.ref;
    (e === null && n !== null || e !== null && e.ref !== n) && (t.flags |= 512, t.flags |= 2097152);
  }
  function Do(e, t, n, r, l) {
    var i = gt(n) ? Vn : it.current;
    return i = vr(t, i), Sr(t, l), n = zo(e, t, n, r, i, l), r = Lo(), e !== null && !wt ? (t.updateQueue = e.updateQueue, t.flags &= -2053, e.lanes &= ~l, yn(e, t, l)) : (Te && r && co(t), t.flags |= 1, ct(e, t, n, l), t.child);
  }
  function fa(e, t, n, r, l) {
    if (gt(n)) {
      var i = !0;
      Vl(t);
    } else i = !1;
    if (Sr(t, l), t.stateNode === null) si(e, t), bs(t, n, r), Io(t, n, r, l), r = !0;
    else if (e === null) {
      var o = t.stateNode, s = t.memoizedProps;
      o.props = s;
      var a = o.context, g = n.contextType;
      typeof g == "object" && g !== null ? g = Tt(g) : (g = gt(n) ? Vn : it.current, g = vr(t, g));
      var E = n.getDerivedStateFromProps, _ = typeof E == "function" || typeof o.getSnapshotBeforeUpdate == "function";
      _ || typeof o.UNSAFE_componentWillReceiveProps != "function" && typeof o.componentWillReceiveProps != "function" || (s !== r || a !== g) && ea(t, o, r, g), Tn = !1;
      var S = t.memoizedState;
      o.state = S, bl(t, r, o, l), a = t.memoizedState, s !== r || S !== a || yt.current || Tn ? (typeof E == "function" && (Oo(t, n, E, r), a = t.memoizedState), (s = Tn || Js(t, n, s, r, S, a, g)) ? (_ || typeof o.UNSAFE_componentWillMount != "function" && typeof o.componentWillMount != "function" || (typeof o.componentWillMount == "function" && o.componentWillMount(), typeof o.UNSAFE_componentWillMount == "function" && o.UNSAFE_componentWillMount()), typeof o.componentDidMount == "function" && (t.flags |= 4194308)) : (typeof o.componentDidMount == "function" && (t.flags |= 4194308), t.memoizedProps = r, t.memoizedState = a), o.props = r, o.state = a, o.context = g, r = s) : (typeof o.componentDidMount == "function" && (t.flags |= 4194308), r = !1);
    } else {
      o = t.stateNode, js(e, t), s = t.memoizedProps, g = t.type === t.elementType ? s : Ht(t.type, s), o.props = g, _ = t.pendingProps, S = o.context, a = n.contextType, typeof a == "object" && a !== null ? a = Tt(a) : (a = gt(n) ? Vn : it.current, a = vr(t, a));
      var M = n.getDerivedStateFromProps;
      (E = typeof M == "function" || typeof o.getSnapshotBeforeUpdate == "function") || typeof o.UNSAFE_componentWillReceiveProps != "function" && typeof o.componentWillReceiveProps != "function" || (s !== _ || S !== a) && ea(t, o, r, a), Tn = !1, S = t.memoizedState, o.state = S, bl(t, r, o, l);
      var A = t.memoizedState;
      s !== _ || S !== A || yt.current || Tn ? (typeof M == "function" && (Oo(t, n, M, r), A = t.memoizedState), (g = Tn || Js(t, n, g, r, S, A, a) || !1) ? (E || typeof o.UNSAFE_componentWillUpdate != "function" && typeof o.componentWillUpdate != "function" || (typeof o.componentWillUpdate == "function" && o.componentWillUpdate(r, A, a), typeof o.UNSAFE_componentWillUpdate == "function" && o.UNSAFE_componentWillUpdate(r, A, a)), typeof o.componentDidUpdate == "function" && (t.flags |= 4), typeof o.getSnapshotBeforeUpdate == "function" && (t.flags |= 1024)) : (typeof o.componentDidUpdate != "function" || s === e.memoizedProps && S === e.memoizedState || (t.flags |= 4), typeof o.getSnapshotBeforeUpdate != "function" || s === e.memoizedProps && S === e.memoizedState || (t.flags |= 1024), t.memoizedProps = r, t.memoizedState = A), o.props = r, o.state = A, o.context = a, r = g) : (typeof o.componentDidUpdate != "function" || s === e.memoizedProps && S === e.memoizedState || (t.flags |= 4), typeof o.getSnapshotBeforeUpdate != "function" || s === e.memoizedProps && S === e.memoizedState || (t.flags |= 1024), r = !1);
    }
    return Uo(e, t, n, r, i, l);
  }
  function Uo(e, t, n, r, l, i) {
    ca(e, t);
    var o = (t.flags & 128) !== 0;
    if (!r && !o) return l && vs(t, n, !1), yn(e, t, i);
    r = t.stateNode, Mf.current = t;
    var s = o && typeof n.getDerivedStateFromError != "function" ? null : r.render();
    return t.flags |= 1, e !== null && o ? (t.child = xr(t, e.child, null, i), t.child = xr(t, null, s, i)) : ct(e, t, s, i), t.memoizedState = r.state, l && vs(t, n, !0), t.child;
  }
  function da(e) {
    var t = e.stateNode;
    t.pendingContext ? hs(e, t.pendingContext, t.pendingContext !== t.context) : t.context && hs(e, t.context, !1), So(e, t.containerInfo);
  }
  function pa(e, t, n, r, l) {
    return wr(), mo(l), t.flags |= 256, ct(e, t, n, r), t.child;
  }
  var $o = { dehydrated: null, treeContext: null, retryLane: 0 };
  function Wo(e) {
    return { baseLanes: e, cachePool: null, transitions: null };
  }
  function ha(e, t, n) {
    var r = t.pendingProps, l = Fe.current, i = !1, o = (t.flags & 128) !== 0, s;
    if ((s = o) || (s = e !== null && e.memoizedState === null ? !1 : (l & 2) !== 0), s ? (i = !0, t.flags &= -129) : (e === null || e.memoizedState !== null) && (l |= 1), Ce(Fe, l & 1), e === null)
      return ho(t), e = t.memoizedState, e !== null && (e = e.dehydrated, e !== null) ? ((t.mode & 1) === 0 ? t.lanes = 1 : e.data === "$!" ? t.lanes = 8 : t.lanes = 1073741824, null) : (o = r.children, e = r.fallback, i ? (r = t.mode, i = t.child, o = { mode: "hidden", children: o }, (r & 1) === 0 && i !== null ? (i.childLanes = 0, i.pendingProps = o) : i = xi(o, r, 0, null), e = er(e, r, n, null), i.return = t, e.return = t, i.sibling = e, t.child = i, t.child.memoizedState = Wo(n), t.memoizedState = $o, e) : Bo(t, o));
    if (l = e.memoizedState, l !== null && (s = l.dehydrated, s !== null)) return Of(e, t, o, r, s, l, n);
    if (i) {
      i = r.fallback, o = t.mode, l = e.child, s = l.sibling;
      var a = { mode: "hidden", children: r.children };
      return (o & 1) === 0 && t.child !== l ? (r = t.child, r.childLanes = 0, r.pendingProps = a, t.deletions = null) : (r = Un(l, a), r.subtreeFlags = l.subtreeFlags & 14680064), s !== null ? i = Un(s, i) : (i = er(i, o, n, null), i.flags |= 2), i.return = t, r.return = t, r.sibling = i, t.child = r, r = i, i = t.child, o = e.child.memoizedState, o = o === null ? Wo(n) : { baseLanes: o.baseLanes | n, cachePool: null, transitions: o.transitions }, i.memoizedState = o, i.childLanes = e.childLanes & ~n, t.memoizedState = $o, r;
    }
    return i = e.child, e = i.sibling, r = Un(i, { mode: "visible", children: r.children }), (t.mode & 1) === 0 && (r.lanes = n), r.return = t, r.sibling = null, e !== null && (n = t.deletions, n === null ? (t.deletions = [e], t.flags |= 16) : n.push(e)), t.child = r, t.memoizedState = null, r;
  }
  function Bo(e, t) {
    return t = xi({ mode: "visible", children: t }, e.mode, 0, null), t.return = e, e.child = t;
  }
  function ui(e, t, n, r) {
    return r !== null && mo(r), xr(t, e.child, null, n), e = Bo(t, t.pendingProps.children), e.flags |= 2, t.memoizedState = null, e;
  }
  function Of(e, t, n, r, l, i, o) {
    if (n)
      return t.flags & 256 ? (t.flags &= -257, r = Fo(Error(f(422))), ui(e, t, o, r)) : t.memoizedState !== null ? (t.child = e.child, t.flags |= 128, null) : (i = r.fallback, l = t.mode, r = xi({ mode: "visible", children: r.children }, l, 0, null), i = er(i, l, o, null), i.flags |= 2, r.return = t, i.return = t, r.sibling = i, t.child = r, (t.mode & 1) !== 0 && xr(t, e.child, null, o), t.child.memoizedState = Wo(o), t.memoizedState = $o, i);
    if ((t.mode & 1) === 0) return ui(e, t, o, null);
    if (l.data === "$!") {
      if (r = l.nextSibling && l.nextSibling.dataset, r) var s = r.dgst;
      return r = s, i = Error(f(419)), r = Fo(i, r, void 0), ui(e, t, o, r);
    }
    if (s = (o & e.childLanes) !== 0, wt || s) {
      if (r = qe, r !== null) {
        switch (o & -o) {
          case 4:
            l = 2;
            break;
          case 16:
            l = 8;
            break;
          case 64:
          case 128:
          case 256:
          case 512:
          case 1024:
          case 2048:
          case 4096:
          case 8192:
          case 16384:
          case 32768:
          case 65536:
          case 131072:
          case 262144:
          case 524288:
          case 1048576:
          case 2097152:
          case 4194304:
          case 8388608:
          case 16777216:
          case 33554432:
          case 67108864:
            l = 32;
            break;
          case 536870912:
            l = 268435456;
            break;
          default:
            l = 0;
        }
        l = (l & (r.suspendedLanes | o)) !== 0 ? 0 : l, l !== 0 && l !== i.retryLane && (i.retryLane = l, mn(e, l), Kt(r, e, l, -1));
      }
      return lu(), r = Fo(Error(f(421))), ui(e, t, o, r);
    }
    return l.data === "$?" ? (t.flags |= 128, t.child = e.child, t = Yf.bind(null, e), l._reactRetry = t, null) : (e = i.treeContext, zt = zn(l.nextSibling), jt = t, Te = !0, Bt = null, e !== null && (Pt[Rt++] = pn, Pt[Rt++] = hn, Pt[Rt++] = Qn, pn = e.id, hn = e.overflow, Qn = t), t = Bo(t, r.children), t.flags |= 4096, t);
  }
  function ma(e, t, n) {
    e.lanes |= t;
    var r = e.alternate;
    r !== null && (r.lanes |= t), wo(e.return, t, n);
  }
  function Ho(e, t, n, r, l) {
    var i = e.memoizedState;
    i === null ? e.memoizedState = { isBackwards: t, rendering: null, renderingStartTime: 0, last: r, tail: n, tailMode: l } : (i.isBackwards = t, i.rendering = null, i.renderingStartTime = 0, i.last = r, i.tail = n, i.tailMode = l);
  }
  function va(e, t, n) {
    var r = t.pendingProps, l = r.revealOrder, i = r.tail;
    if (ct(e, t, r.children, n), r = Fe.current, (r & 2) !== 0) r = r & 1 | 2, t.flags |= 128;
    else {
      if (e !== null && (e.flags & 128) !== 0) e: for (e = t.child; e !== null; ) {
        if (e.tag === 13) e.memoizedState !== null && ma(e, n, t);
        else if (e.tag === 19) ma(e, n, t);
        else if (e.child !== null) {
          e.child.return = e, e = e.child;
          continue;
        }
        if (e === t) break e;
        for (; e.sibling === null; ) {
          if (e.return === null || e.return === t) break e;
          e = e.return;
        }
        e.sibling.return = e.return, e = e.sibling;
      }
      r &= 1;
    }
    if (Ce(Fe, r), (t.mode & 1) === 0) t.memoizedState = null;
    else switch (l) {
      case "forwards":
        for (n = t.child, l = null; n !== null; ) e = n.alternate, e !== null && ei(e) === null && (l = n), n = n.sibling;
        n = l, n === null ? (l = t.child, t.child = null) : (l = n.sibling, n.sibling = null), Ho(t, !1, l, n, i);
        break;
      case "backwards":
        for (n = null, l = t.child, t.child = null; l !== null; ) {
          if (e = l.alternate, e !== null && ei(e) === null) {
            t.child = l;
            break;
          }
          e = l.sibling, l.sibling = n, n = l, l = e;
        }
        Ho(t, !0, n, null, i);
        break;
      case "together":
        Ho(t, !1, null, null, void 0);
        break;
      default:
        t.memoizedState = null;
    }
    return t.child;
  }
  function si(e, t) {
    (t.mode & 1) === 0 && e !== null && (e.alternate = null, t.alternate = null, t.flags |= 2);
  }
  function yn(e, t, n) {
    if (e !== null && (t.dependencies = e.dependencies), Zn |= t.lanes, (n & t.childLanes) === 0) return null;
    if (e !== null && t.child !== e.child) throw Error(f(153));
    if (t.child !== null) {
      for (e = t.child, n = Un(e, e.pendingProps), t.child = n, n.return = t; e.sibling !== null; ) e = e.sibling, n = n.sibling = Un(e, e.pendingProps), n.return = t;
      n.sibling = null;
    }
    return t.child;
  }
  function If(e, t, n) {
    switch (t.tag) {
      case 3:
        da(t), wr();
        break;
      case 5:
        Ps(t);
        break;
      case 1:
        gt(t.type) && Vl(t);
        break;
      case 4:
        So(t, t.stateNode.containerInfo);
        break;
      case 10:
        var r = t.type._context, l = t.memoizedProps.value;
        Ce(Zl, r._currentValue), r._currentValue = l;
        break;
      case 13:
        if (r = t.memoizedState, r !== null)
          return r.dehydrated !== null ? (Ce(Fe, Fe.current & 1), t.flags |= 128, null) : (n & t.child.childLanes) !== 0 ? ha(e, t, n) : (Ce(Fe, Fe.current & 1), e = yn(e, t, n), e !== null ? e.sibling : null);
        Ce(Fe, Fe.current & 1);
        break;
      case 19:
        if (r = (n & t.childLanes) !== 0, (e.flags & 128) !== 0) {
          if (r) return va(e, t, n);
          t.flags |= 128;
        }
        if (l = t.memoizedState, l !== null && (l.rendering = null, l.tail = null, l.lastEffect = null), Ce(Fe, Fe.current), r) break;
        return null;
      case 22:
      case 23:
        return t.lanes = 0, aa(e, t, n);
    }
    return yn(e, t, n);
  }
  var ya, Vo, ga, wa;
  ya = function(e, t) {
    for (var n = t.child; n !== null; ) {
      if (n.tag === 5 || n.tag === 6) e.appendChild(n.stateNode);
      else if (n.tag !== 4 && n.child !== null) {
        n.child.return = n, n = n.child;
        continue;
      }
      if (n === t) break;
      for (; n.sibling === null; ) {
        if (n.return === null || n.return === t) return;
        n = n.return;
      }
      n.sibling.return = n.return, n = n.sibling;
    }
  }, Vo = function() {
  }, ga = function(e, t, n, r) {
    var l = e.memoizedProps;
    if (l !== r) {
      e = t.stateNode, Xn(bt.current);
      var i = null;
      switch (n) {
        case "input":
          l = Ve(e, l), r = Ve(e, r), i = [];
          break;
        case "select":
          l = P({}, l, { value: void 0 }), r = P({}, r, { value: void 0 }), i = [];
          break;
        case "textarea":
          l = _t(e, l), r = _t(e, r), i = [];
          break;
        default:
          typeof l.onClick != "function" && typeof r.onClick == "function" && (e.onclick = Wl);
      }
      sn(n, r);
      var o;
      n = null;
      for (g in l) if (!r.hasOwnProperty(g) && l.hasOwnProperty(g) && l[g] != null) if (g === "style") {
        var s = l[g];
        for (o in s) s.hasOwnProperty(o) && (n || (n = {}), n[o] = "");
      } else g !== "dangerouslySetInnerHTML" && g !== "children" && g !== "suppressContentEditableWarning" && g !== "suppressHydrationWarning" && g !== "autoFocus" && (j.hasOwnProperty(g) ? i || (i = []) : (i = i || []).push(g, null));
      for (g in r) {
        var a = r[g];
        if (s = l != null ? l[g] : void 0, r.hasOwnProperty(g) && a !== s && (a != null || s != null)) if (g === "style") if (s) {
          for (o in s) !s.hasOwnProperty(o) || a && a.hasOwnProperty(o) || (n || (n = {}), n[o] = "");
          for (o in a) a.hasOwnProperty(o) && s[o] !== a[o] && (n || (n = {}), n[o] = a[o]);
        } else n || (i || (i = []), i.push(
          g,
          n
        )), n = a;
        else g === "dangerouslySetInnerHTML" ? (a = a ? a.__html : void 0, s = s ? s.__html : void 0, a != null && s !== a && (i = i || []).push(g, a)) : g === "children" ? typeof a != "string" && typeof a != "number" || (i = i || []).push(g, "" + a) : g !== "suppressContentEditableWarning" && g !== "suppressHydrationWarning" && (j.hasOwnProperty(g) ? (a != null && g === "onScroll" && Le("scroll", e), i || s === a || (i = [])) : (i = i || []).push(g, a));
      }
      n && (i = i || []).push("style", n);
      var g = i;
      (t.updateQueue = g) && (t.flags |= 4);
    }
  }, wa = function(e, t, n, r) {
    n !== r && (t.flags |= 4);
  };
  function cl(e, t) {
    if (!Te) switch (e.tailMode) {
      case "hidden":
        t = e.tail;
        for (var n = null; t !== null; ) t.alternate !== null && (n = t), t = t.sibling;
        n === null ? e.tail = null : n.sibling = null;
        break;
      case "collapsed":
        n = e.tail;
        for (var r = null; n !== null; ) n.alternate !== null && (r = n), n = n.sibling;
        r === null ? t || e.tail === null ? e.tail = null : e.tail.sibling = null : r.sibling = null;
    }
  }
  function ut(e) {
    var t = e.alternate !== null && e.alternate.child === e.child, n = 0, r = 0;
    if (t) for (var l = e.child; l !== null; ) n |= l.lanes | l.childLanes, r |= l.subtreeFlags & 14680064, r |= l.flags & 14680064, l.return = e, l = l.sibling;
    else for (l = e.child; l !== null; ) n |= l.lanes | l.childLanes, r |= l.subtreeFlags, r |= l.flags, l.return = e, l = l.sibling;
    return e.subtreeFlags |= r, e.childLanes = n, t;
  }
  function Ff(e, t, n) {
    var r = t.pendingProps;
    switch (fo(t), t.tag) {
      case 2:
      case 16:
      case 15:
      case 0:
      case 11:
      case 7:
      case 8:
      case 12:
      case 9:
      case 14:
        return ut(t), null;
      case 1:
        return gt(t.type) && Hl(), ut(t), null;
      case 3:
        return r = t.stateNode, Er(), Pe(yt), Pe(it), Co(), r.pendingContext && (r.context = r.pendingContext, r.pendingContext = null), (e === null || e.child === null) && (Xl(t) ? t.flags |= 4 : e === null || e.memoizedState.isDehydrated && (t.flags & 256) === 0 || (t.flags |= 1024, Bt !== null && (tu(Bt), Bt = null))), Vo(e, t), ut(t), null;
      case 5:
        Eo(t);
        var l = Xn(il.current);
        if (n = t.type, e !== null && t.stateNode != null) ga(e, t, n, r, l), e.ref !== t.ref && (t.flags |= 512, t.flags |= 2097152);
        else {
          if (!r) {
            if (t.stateNode === null) throw Error(f(166));
            return ut(t), null;
          }
          if (e = Xn(bt.current), Xl(t)) {
            r = t.stateNode, n = t.type;
            var i = t.memoizedProps;
            switch (r[Jt] = t, r[el] = i, e = (t.mode & 1) !== 0, n) {
              case "dialog":
                Le("cancel", r), Le("close", r);
                break;
              case "iframe":
              case "object":
              case "embed":
                Le("load", r);
                break;
              case "video":
              case "audio":
                for (l = 0; l < qr.length; l++) Le(qr[l], r);
                break;
              case "source":
                Le("error", r);
                break;
              case "img":
              case "image":
              case "link":
                Le(
                  "error",
                  r
                ), Le("load", r);
                break;
              case "details":
                Le("toggle", r);
                break;
              case "input":
                me(r, i), Le("invalid", r);
                break;
              case "select":
                r._wrapperState = { wasMultiple: !!i.multiple }, Le("invalid", r);
                break;
              case "textarea":
                Ft(r, i), Le("invalid", r);
            }
            sn(n, i), l = null;
            for (var o in i) if (i.hasOwnProperty(o)) {
              var s = i[o];
              o === "children" ? typeof s == "string" ? r.textContent !== s && (i.suppressHydrationWarning !== !0 && $l(r.textContent, s, e), l = ["children", s]) : typeof s == "number" && r.textContent !== "" + s && (i.suppressHydrationWarning !== !0 && $l(
                r.textContent,
                s,
                e
              ), l = ["children", "" + s]) : j.hasOwnProperty(o) && s != null && o === "onScroll" && Le("scroll", r);
            }
            switch (n) {
              case "input":
                ne(r), et(r, i, !0);
                break;
              case "textarea":
                ne(r), ln(r);
                break;
              case "select":
              case "option":
                break;
              default:
                typeof i.onClick == "function" && (r.onclick = Wl);
            }
            r = l, t.updateQueue = r, r !== null && (t.flags |= 4);
          } else {
            o = l.nodeType === 9 ? l : l.ownerDocument, e === "http://www.w3.org/1999/xhtml" && (e = pt(n)), e === "http://www.w3.org/1999/xhtml" ? n === "script" ? (e = o.createElement("div"), e.innerHTML = "<script><\/script>", e = e.removeChild(e.firstChild)) : typeof r.is == "string" ? e = o.createElement(n, { is: r.is }) : (e = o.createElement(n), n === "select" && (o = e, r.multiple ? o.multiple = !0 : r.size && (o.size = r.size))) : e = o.createElementNS(e, n), e[Jt] = t, e[el] = r, ya(e, t, !1, !1), t.stateNode = e;
            e: {
              switch (o = an(n, r), n) {
                case "dialog":
                  Le("cancel", e), Le("close", e), l = r;
                  break;
                case "iframe":
                case "object":
                case "embed":
                  Le("load", e), l = r;
                  break;
                case "video":
                case "audio":
                  for (l = 0; l < qr.length; l++) Le(qr[l], e);
                  l = r;
                  break;
                case "source":
                  Le("error", e), l = r;
                  break;
                case "img":
                case "image":
                case "link":
                  Le(
                    "error",
                    e
                  ), Le("load", e), l = r;
                  break;
                case "details":
                  Le("toggle", e), l = r;
                  break;
                case "input":
                  me(e, r), l = Ve(e, r), Le("invalid", e);
                  break;
                case "option":
                  l = r;
                  break;
                case "select":
                  e._wrapperState = { wasMultiple: !!r.multiple }, l = P({}, r, { value: void 0 }), Le("invalid", e);
                  break;
                case "textarea":
                  Ft(e, r), l = _t(e, r), Le("invalid", e);
                  break;
                default:
                  l = r;
              }
              sn(n, l), s = l;
              for (i in s) if (s.hasOwnProperty(i)) {
                var a = s[i];
                i === "style" ? un(e, a) : i === "dangerouslySetInnerHTML" ? (a = a ? a.__html : void 0, a != null && wn(e, a)) : i === "children" ? typeof a == "string" ? (n !== "textarea" || a !== "") && tt(e, a) : typeof a == "number" && tt(e, "" + a) : i !== "suppressContentEditableWarning" && i !== "suppressHydrationWarning" && i !== "autoFocus" && (j.hasOwnProperty(i) ? a != null && i === "onScroll" && Le("scroll", e) : a != null && Me(e, i, a, o));
              }
              switch (n) {
                case "input":
                  ne(e), et(e, r, !1);
                  break;
                case "textarea":
                  ne(e), ln(e);
                  break;
                case "option":
                  r.value != null && e.setAttribute("value", "" + Y(r.value));
                  break;
                case "select":
                  e.multiple = !!r.multiple, i = r.value, i != null ? dt(e, !!r.multiple, i, !1) : r.defaultValue != null && dt(
                    e,
                    !!r.multiple,
                    r.defaultValue,
                    !0
                  );
                  break;
                default:
                  typeof l.onClick == "function" && (e.onclick = Wl);
              }
              switch (n) {
                case "button":
                case "input":
                case "select":
                case "textarea":
                  r = !!r.autoFocus;
                  break e;
                case "img":
                  r = !0;
                  break e;
                default:
                  r = !1;
              }
            }
            r && (t.flags |= 4);
          }
          t.ref !== null && (t.flags |= 512, t.flags |= 2097152);
        }
        return ut(t), null;
      case 6:
        if (e && t.stateNode != null) wa(e, t, e.memoizedProps, r);
        else {
          if (typeof r != "string" && t.stateNode === null) throw Error(f(166));
          if (n = Xn(il.current), Xn(bt.current), Xl(t)) {
            if (r = t.stateNode, n = t.memoizedProps, r[Jt] = t, (i = r.nodeValue !== n) && (e = jt, e !== null)) switch (e.tag) {
              case 3:
                $l(r.nodeValue, n, (e.mode & 1) !== 0);
                break;
              case 5:
                e.memoizedProps.suppressHydrationWarning !== !0 && $l(r.nodeValue, n, (e.mode & 1) !== 0);
            }
            i && (t.flags |= 4);
          } else r = (n.nodeType === 9 ? n : n.ownerDocument).createTextNode(r), r[Jt] = t, t.stateNode = r;
        }
        return ut(t), null;
      case 13:
        if (Pe(Fe), r = t.memoizedState, e === null || e.memoizedState !== null && e.memoizedState.dehydrated !== null) {
          if (Te && zt !== null && (t.mode & 1) !== 0 && (t.flags & 128) === 0) Ss(), wr(), t.flags |= 98560, i = !1;
          else if (i = Xl(t), r !== null && r.dehydrated !== null) {
            if (e === null) {
              if (!i) throw Error(f(318));
              if (i = t.memoizedState, i = i !== null ? i.dehydrated : null, !i) throw Error(f(317));
              i[Jt] = t;
            } else wr(), (t.flags & 128) === 0 && (t.memoizedState = null), t.flags |= 4;
            ut(t), i = !1;
          } else Bt !== null && (tu(Bt), Bt = null), i = !0;
          if (!i) return t.flags & 65536 ? t : null;
        }
        return (t.flags & 128) !== 0 ? (t.lanes = n, t) : (r = r !== null, r !== (e !== null && e.memoizedState !== null) && r && (t.child.flags |= 8192, (t.mode & 1) !== 0 && (e === null || (Fe.current & 1) !== 0 ? Ke === 0 && (Ke = 3) : lu())), t.updateQueue !== null && (t.flags |= 4), ut(t), null);
      case 4:
        return Er(), Vo(e, t), e === null && Jr(t.stateNode.containerInfo), ut(t), null;
      case 10:
        return go(t.type._context), ut(t), null;
      case 17:
        return gt(t.type) && Hl(), ut(t), null;
      case 19:
        if (Pe(Fe), i = t.memoizedState, i === null) return ut(t), null;
        if (r = (t.flags & 128) !== 0, o = i.rendering, o === null) if (r) cl(i, !1);
        else {
          if (Ke !== 0 || e !== null && (e.flags & 128) !== 0) for (e = t.child; e !== null; ) {
            if (o = ei(e), o !== null) {
              for (t.flags |= 128, cl(i, !1), r = o.updateQueue, r !== null && (t.updateQueue = r, t.flags |= 4), t.subtreeFlags = 0, r = n, n = t.child; n !== null; ) i = n, e = r, i.flags &= 14680066, o = i.alternate, o === null ? (i.childLanes = 0, i.lanes = e, i.child = null, i.subtreeFlags = 0, i.memoizedProps = null, i.memoizedState = null, i.updateQueue = null, i.dependencies = null, i.stateNode = null) : (i.childLanes = o.childLanes, i.lanes = o.lanes, i.child = o.child, i.subtreeFlags = 0, i.deletions = null, i.memoizedProps = o.memoizedProps, i.memoizedState = o.memoizedState, i.updateQueue = o.updateQueue, i.type = o.type, e = o.dependencies, i.dependencies = e === null ? null : { lanes: e.lanes, firstContext: e.firstContext }), n = n.sibling;
              return Ce(Fe, Fe.current & 1 | 2), t.child;
            }
            e = e.sibling;
          }
          i.tail !== null && $e() > jr && (t.flags |= 128, r = !0, cl(i, !1), t.lanes = 4194304);
        }
        else {
          if (!r) if (e = ei(o), e !== null) {
            if (t.flags |= 128, r = !0, n = e.updateQueue, n !== null && (t.updateQueue = n, t.flags |= 4), cl(i, !0), i.tail === null && i.tailMode === "hidden" && !o.alternate && !Te) return ut(t), null;
          } else 2 * $e() - i.renderingStartTime > jr && n !== 1073741824 && (t.flags |= 128, r = !0, cl(i, !1), t.lanes = 4194304);
          i.isBackwards ? (o.sibling = t.child, t.child = o) : (n = i.last, n !== null ? n.sibling = o : t.child = o, i.last = o);
        }
        return i.tail !== null ? (t = i.tail, i.rendering = t, i.tail = t.sibling, i.renderingStartTime = $e(), t.sibling = null, n = Fe.current, Ce(Fe, r ? n & 1 | 2 : n & 1), t) : (ut(t), null);
      case 22:
      case 23:
        return ru(), r = t.memoizedState !== null, e !== null && e.memoizedState !== null !== r && (t.flags |= 8192), r && (t.mode & 1) !== 0 ? (Lt & 1073741824) !== 0 && (ut(t), t.subtreeFlags & 6 && (t.flags |= 8192)) : ut(t), null;
      case 24:
        return null;
      case 25:
        return null;
    }
    throw Error(f(156, t.tag));
  }
  function Af(e, t) {
    switch (fo(t), t.tag) {
      case 1:
        return gt(t.type) && Hl(), e = t.flags, e & 65536 ? (t.flags = e & -65537 | 128, t) : null;
      case 3:
        return Er(), Pe(yt), Pe(it), Co(), e = t.flags, (e & 65536) !== 0 && (e & 128) === 0 ? (t.flags = e & -65537 | 128, t) : null;
      case 5:
        return Eo(t), null;
      case 13:
        if (Pe(Fe), e = t.memoizedState, e !== null && e.dehydrated !== null) {
          if (t.alternate === null) throw Error(f(340));
          wr();
        }
        return e = t.flags, e & 65536 ? (t.flags = e & -65537 | 128, t) : null;
      case 19:
        return Pe(Fe), null;
      case 4:
        return Er(), null;
      case 10:
        return go(t.type._context), null;
      case 22:
      case 23:
        return ru(), null;
      case 24:
        return null;
      default:
        return null;
    }
  }
  var ai = !1, st = !1, Df = typeof WeakSet == "function" ? WeakSet : Set, F = null;
  function Cr(e, t) {
    var n = e.ref;
    if (n !== null) if (typeof n == "function") try {
      n(null);
    } catch (r) {
      Ue(e, t, r);
    }
    else n.current = null;
  }
  function Qo(e, t, n) {
    try {
      n();
    } catch (r) {
      Ue(e, t, r);
    }
  }
  var xa = !1;
  function Uf(e, t) {
    if (no = Ll, e = Ju(), Xi(e)) {
      if ("selectionStart" in e) var n = { start: e.selectionStart, end: e.selectionEnd };
      else e: {
        n = (n = e.ownerDocument) && n.defaultView || window;
        var r = n.getSelection && n.getSelection();
        if (r && r.rangeCount !== 0) {
          n = r.anchorNode;
          var l = r.anchorOffset, i = r.focusNode;
          r = r.focusOffset;
          try {
            n.nodeType, i.nodeType;
          } catch {
            n = null;
            break e;
          }
          var o = 0, s = -1, a = -1, g = 0, E = 0, _ = e, S = null;
          t: for (; ; ) {
            for (var M; _ !== n || l !== 0 && _.nodeType !== 3 || (s = o + l), _ !== i || r !== 0 && _.nodeType !== 3 || (a = o + r), _.nodeType === 3 && (o += _.nodeValue.length), (M = _.firstChild) !== null; )
              S = _, _ = M;
            for (; ; ) {
              if (_ === e) break t;
              if (S === n && ++g === l && (s = o), S === i && ++E === r && (a = o), (M = _.nextSibling) !== null) break;
              _ = S, S = _.parentNode;
            }
            _ = M;
          }
          n = s === -1 || a === -1 ? null : { start: s, end: a };
        } else n = null;
      }
      n = n || { start: 0, end: 0 };
    } else n = null;
    for (ro = { focusedElem: e, selectionRange: n }, Ll = !1, F = t; F !== null; ) if (t = F, e = t.child, (t.subtreeFlags & 1028) !== 0 && e !== null) e.return = t, F = e;
    else for (; F !== null; ) {
      t = F;
      try {
        var A = t.alternate;
        if ((t.flags & 1024) !== 0) switch (t.tag) {
          case 0:
          case 11:
          case 15:
            break;
          case 1:
            if (A !== null) {
              var U = A.memoizedProps, We = A.memoizedState, h = t.stateNode, p = h.getSnapshotBeforeUpdate(t.elementType === t.type ? U : Ht(t.type, U), We);
              h.__reactInternalSnapshotBeforeUpdate = p;
            }
            break;
          case 3:
            var v = t.stateNode.containerInfo;
            v.nodeType === 1 ? v.textContent = "" : v.nodeType === 9 && v.documentElement && v.removeChild(v.documentElement);
            break;
          case 5:
          case 6:
          case 4:
          case 17:
            break;
          default:
            throw Error(f(163));
        }
      } catch (z) {
        Ue(t, t.return, z);
      }
      if (e = t.sibling, e !== null) {
        e.return = t.return, F = e;
        break;
      }
      F = t.return;
    }
    return A = xa, xa = !1, A;
  }
  function fl(e, t, n) {
    var r = t.updateQueue;
    if (r = r !== null ? r.lastEffect : null, r !== null) {
      var l = r = r.next;
      do {
        if ((l.tag & e) === e) {
          var i = l.destroy;
          l.destroy = void 0, i !== void 0 && Qo(t, n, i);
        }
        l = l.next;
      } while (l !== r);
    }
  }
  function ci(e, t) {
    if (t = t.updateQueue, t = t !== null ? t.lastEffect : null, t !== null) {
      var n = t = t.next;
      do {
        if ((n.tag & e) === e) {
          var r = n.create;
          n.destroy = r();
        }
        n = n.next;
      } while (n !== t);
    }
  }
  function Ko(e) {
    var t = e.ref;
    if (t !== null) {
      var n = e.stateNode;
      switch (e.tag) {
        case 5:
          e = n;
          break;
        default:
          e = n;
      }
      typeof t == "function" ? t(e) : t.current = e;
    }
  }
  function ka(e) {
    var t = e.alternate;
    t !== null && (e.alternate = null, ka(t)), e.child = null, e.deletions = null, e.sibling = null, e.tag === 5 && (t = e.stateNode, t !== null && (delete t[Jt], delete t[el], delete t[uo], delete t[kf], delete t[Sf])), e.stateNode = null, e.return = null, e.dependencies = null, e.memoizedProps = null, e.memoizedState = null, e.pendingProps = null, e.stateNode = null, e.updateQueue = null;
  }
  function Sa(e) {
    return e.tag === 5 || e.tag === 3 || e.tag === 4;
  }
  function Ea(e) {
    e: for (; ; ) {
      for (; e.sibling === null; ) {
        if (e.return === null || Sa(e.return)) return null;
        e = e.return;
      }
      for (e.sibling.return = e.return, e = e.sibling; e.tag !== 5 && e.tag !== 6 && e.tag !== 18; ) {
        if (e.flags & 2 || e.child === null || e.tag === 4) continue e;
        e.child.return = e, e = e.child;
      }
      if (!(e.flags & 2)) return e.stateNode;
    }
  }
  function Yo(e, t, n) {
    var r = e.tag;
    if (r === 5 || r === 6) e = e.stateNode, t ? n.nodeType === 8 ? n.parentNode.insertBefore(e, t) : n.insertBefore(e, t) : (n.nodeType === 8 ? (t = n.parentNode, t.insertBefore(e, n)) : (t = n, t.appendChild(e)), n = n._reactRootContainer, n != null || t.onclick !== null || (t.onclick = Wl));
    else if (r !== 4 && (e = e.child, e !== null)) for (Yo(e, t, n), e = e.sibling; e !== null; ) Yo(e, t, n), e = e.sibling;
  }
  function Xo(e, t, n) {
    var r = e.tag;
    if (r === 5 || r === 6) e = e.stateNode, t ? n.insertBefore(e, t) : n.appendChild(e);
    else if (r !== 4 && (e = e.child, e !== null)) for (Xo(e, t, n), e = e.sibling; e !== null; ) Xo(e, t, n), e = e.sibling;
  }
  var rt = null, Vt = !1;
  function On(e, t, n) {
    for (n = n.child; n !== null; ) _a(e, t, n), n = n.sibling;
  }
  function _a(e, t, n) {
    if (qt && typeof qt.onCommitFiberUnmount == "function") try {
      qt.onCommitFiberUnmount(El, n);
    } catch {
    }
    switch (n.tag) {
      case 5:
        st || Cr(n, t);
      case 6:
        var r = rt, l = Vt;
        rt = null, On(e, t, n), rt = r, Vt = l, rt !== null && (Vt ? (e = rt, n = n.stateNode, e.nodeType === 8 ? e.parentNode.removeChild(n) : e.removeChild(n)) : rt.removeChild(n.stateNode));
        break;
      case 18:
        rt !== null && (Vt ? (e = rt, n = n.stateNode, e.nodeType === 8 ? oo(e.parentNode, n) : e.nodeType === 1 && oo(e, n), Hr(e)) : oo(rt, n.stateNode));
        break;
      case 4:
        r = rt, l = Vt, rt = n.stateNode.containerInfo, Vt = !0, On(e, t, n), rt = r, Vt = l;
        break;
      case 0:
      case 11:
      case 14:
      case 15:
        if (!st && (r = n.updateQueue, r !== null && (r = r.lastEffect, r !== null))) {
          l = r = r.next;
          do {
            var i = l, o = i.destroy;
            i = i.tag, o !== void 0 && ((i & 2) !== 0 || (i & 4) !== 0) && Qo(n, t, o), l = l.next;
          } while (l !== r);
        }
        On(e, t, n);
        break;
      case 1:
        if (!st && (Cr(n, t), r = n.stateNode, typeof r.componentWillUnmount == "function")) try {
          r.props = n.memoizedProps, r.state = n.memoizedState, r.componentWillUnmount();
        } catch (s) {
          Ue(n, t, s);
        }
        On(e, t, n);
        break;
      case 21:
        On(e, t, n);
        break;
      case 22:
        n.mode & 1 ? (st = (r = st) || n.memoizedState !== null, On(e, t, n), st = r) : On(e, t, n);
        break;
      default:
        On(e, t, n);
    }
  }
  function Ca(e) {
    var t = e.updateQueue;
    if (t !== null) {
      e.updateQueue = null;
      var n = e.stateNode;
      n === null && (n = e.stateNode = new Df()), t.forEach(function(r) {
        var l = Xf.bind(null, e, r);
        n.has(r) || (n.add(r), r.then(l, l));
      });
    }
  }
  function Qt(e, t) {
    var n = t.deletions;
    if (n !== null) for (var r = 0; r < n.length; r++) {
      var l = n[r];
      try {
        var i = e, o = t, s = o;
        e: for (; s !== null; ) {
          switch (s.tag) {
            case 5:
              rt = s.stateNode, Vt = !1;
              break e;
            case 3:
              rt = s.stateNode.containerInfo, Vt = !0;
              break e;
            case 4:
              rt = s.stateNode.containerInfo, Vt = !0;
              break e;
          }
          s = s.return;
        }
        if (rt === null) throw Error(f(160));
        _a(i, o, l), rt = null, Vt = !1;
        var a = l.alternate;
        a !== null && (a.return = null), l.return = null;
      } catch (g) {
        Ue(l, t, g);
      }
    }
    if (t.subtreeFlags & 12854) for (t = t.child; t !== null; ) Na(t, e), t = t.sibling;
  }
  function Na(e, t) {
    var n = e.alternate, r = e.flags;
    switch (e.tag) {
      case 0:
      case 11:
      case 14:
      case 15:
        if (Qt(t, e), tn(e), r & 4) {
          try {
            fl(3, e, e.return), ci(3, e);
          } catch (U) {
            Ue(e, e.return, U);
          }
          try {
            fl(5, e, e.return);
          } catch (U) {
            Ue(e, e.return, U);
          }
        }
        break;
      case 1:
        Qt(t, e), tn(e), r & 512 && n !== null && Cr(n, n.return);
        break;
      case 5:
        if (Qt(t, e), tn(e), r & 512 && n !== null && Cr(n, n.return), e.flags & 32) {
          var l = e.stateNode;
          try {
            tt(l, "");
          } catch (U) {
            Ue(e, e.return, U);
          }
        }
        if (r & 4 && (l = e.stateNode, l != null)) {
          var i = e.memoizedProps, o = n !== null ? n.memoizedProps : i, s = e.type, a = e.updateQueue;
          if (e.updateQueue = null, a !== null) try {
            s === "input" && i.type === "radio" && i.name != null && rn(l, i), an(s, o);
            var g = an(s, i);
            for (o = 0; o < a.length; o += 2) {
              var E = a[o], _ = a[o + 1];
              E === "style" ? un(l, _) : E === "dangerouslySetInnerHTML" ? wn(l, _) : E === "children" ? tt(l, _) : Me(l, E, _, g);
            }
            switch (s) {
              case "input":
                Ee(l, i);
                break;
              case "textarea":
                At(l, i);
                break;
              case "select":
                var S = l._wrapperState.wasMultiple;
                l._wrapperState.wasMultiple = !!i.multiple;
                var M = i.value;
                M != null ? dt(l, !!i.multiple, M, !1) : S !== !!i.multiple && (i.defaultValue != null ? dt(
                  l,
                  !!i.multiple,
                  i.defaultValue,
                  !0
                ) : dt(l, !!i.multiple, i.multiple ? [] : "", !1));
            }
            l[el] = i;
          } catch (U) {
            Ue(e, e.return, U);
          }
        }
        break;
      case 6:
        if (Qt(t, e), tn(e), r & 4) {
          if (e.stateNode === null) throw Error(f(162));
          l = e.stateNode, i = e.memoizedProps;
          try {
            l.nodeValue = i;
          } catch (U) {
            Ue(e, e.return, U);
          }
        }
        break;
      case 3:
        if (Qt(t, e), tn(e), r & 4 && n !== null && n.memoizedState.isDehydrated) try {
          Hr(t.containerInfo);
        } catch (U) {
          Ue(e, e.return, U);
        }
        break;
      case 4:
        Qt(t, e), tn(e);
        break;
      case 13:
        Qt(t, e), tn(e), l = e.child, l.flags & 8192 && (i = l.memoizedState !== null, l.stateNode.isHidden = i, !i || l.alternate !== null && l.alternate.memoizedState !== null || (qo = $e())), r & 4 && Ca(e);
        break;
      case 22:
        if (E = n !== null && n.memoizedState !== null, e.mode & 1 ? (st = (g = st) || E, Qt(t, e), st = g) : Qt(t, e), tn(e), r & 8192) {
          if (g = e.memoizedState !== null, (e.stateNode.isHidden = g) && !E && (e.mode & 1) !== 0) for (F = e, E = e.child; E !== null; ) {
            for (_ = F = E; F !== null; ) {
              switch (S = F, M = S.child, S.tag) {
                case 0:
                case 11:
                case 14:
                case 15:
                  fl(4, S, S.return);
                  break;
                case 1:
                  Cr(S, S.return);
                  var A = S.stateNode;
                  if (typeof A.componentWillUnmount == "function") {
                    r = S, n = S.return;
                    try {
                      t = r, A.props = t.memoizedProps, A.state = t.memoizedState, A.componentWillUnmount();
                    } catch (U) {
                      Ue(r, n, U);
                    }
                  }
                  break;
                case 5:
                  Cr(S, S.return);
                  break;
                case 22:
                  if (S.memoizedState !== null) {
                    La(_);
                    continue;
                  }
              }
              M !== null ? (M.return = S, F = M) : La(_);
            }
            E = E.sibling;
          }
          e: for (E = null, _ = e; ; ) {
            if (_.tag === 5) {
              if (E === null) {
                E = _;
                try {
                  l = _.stateNode, g ? (i = l.style, typeof i.setProperty == "function" ? i.setProperty("display", "none", "important") : i.display = "none") : (s = _.stateNode, a = _.memoizedProps.style, o = a != null && a.hasOwnProperty("display") ? a.display : null, s.style.display = Tr("display", o));
                } catch (U) {
                  Ue(e, e.return, U);
                }
              }
            } else if (_.tag === 6) {
              if (E === null) try {
                _.stateNode.nodeValue = g ? "" : _.memoizedProps;
              } catch (U) {
                Ue(e, e.return, U);
              }
            } else if ((_.tag !== 22 && _.tag !== 23 || _.memoizedState === null || _ === e) && _.child !== null) {
              _.child.return = _, _ = _.child;
              continue;
            }
            if (_ === e) break e;
            for (; _.sibling === null; ) {
              if (_.return === null || _.return === e) break e;
              E === _ && (E = null), _ = _.return;
            }
            E === _ && (E = null), _.sibling.return = _.return, _ = _.sibling;
          }
        }
        break;
      case 19:
        Qt(t, e), tn(e), r & 4 && Ca(e);
        break;
      case 21:
        break;
      default:
        Qt(
          t,
          e
        ), tn(e);
    }
  }
  function tn(e) {
    var t = e.flags;
    if (t & 2) {
      try {
        e: {
          for (var n = e.return; n !== null; ) {
            if (Sa(n)) {
              var r = n;
              break e;
            }
            n = n.return;
          }
          throw Error(f(160));
        }
        switch (r.tag) {
          case 5:
            var l = r.stateNode;
            r.flags & 32 && (tt(l, ""), r.flags &= -33);
            var i = Ea(e);
            Xo(e, i, l);
            break;
          case 3:
          case 4:
            var o = r.stateNode.containerInfo, s = Ea(e);
            Yo(e, s, o);
            break;
          default:
            throw Error(f(161));
        }
      } catch (a) {
        Ue(e, e.return, a);
      }
      e.flags &= -3;
    }
    t & 4096 && (e.flags &= -4097);
  }
  function $f(e, t, n) {
    F = e, ja(e);
  }
  function ja(e, t, n) {
    for (var r = (e.mode & 1) !== 0; F !== null; ) {
      var l = F, i = l.child;
      if (l.tag === 22 && r) {
        var o = l.memoizedState !== null || ai;
        if (!o) {
          var s = l.alternate, a = s !== null && s.memoizedState !== null || st;
          s = ai;
          var g = st;
          if (ai = o, (st = a) && !g) for (F = l; F !== null; ) o = F, a = o.child, o.tag === 22 && o.memoizedState !== null ? Pa(l) : a !== null ? (a.return = o, F = a) : Pa(l);
          for (; i !== null; ) F = i, ja(i), i = i.sibling;
          F = l, ai = s, st = g;
        }
        za(e);
      } else (l.subtreeFlags & 8772) !== 0 && i !== null ? (i.return = l, F = i) : za(e);
    }
  }
  function za(e) {
    for (; F !== null; ) {
      var t = F;
      if ((t.flags & 8772) !== 0) {
        var n = t.alternate;
        try {
          if ((t.flags & 8772) !== 0) switch (t.tag) {
            case 0:
            case 11:
            case 15:
              st || ci(5, t);
              break;
            case 1:
              var r = t.stateNode;
              if (t.flags & 4 && !st) if (n === null) r.componentDidMount();
              else {
                var l = t.elementType === t.type ? n.memoizedProps : Ht(t.type, n.memoizedProps);
                r.componentDidUpdate(l, n.memoizedState, r.__reactInternalSnapshotBeforeUpdate);
              }
              var i = t.updateQueue;
              i !== null && Ls(t, i, r);
              break;
            case 3:
              var o = t.updateQueue;
              if (o !== null) {
                if (n = null, t.child !== null) switch (t.child.tag) {
                  case 5:
                    n = t.child.stateNode;
                    break;
                  case 1:
                    n = t.child.stateNode;
                }
                Ls(t, o, n);
              }
              break;
            case 5:
              var s = t.stateNode;
              if (n === null && t.flags & 4) {
                n = s;
                var a = t.memoizedProps;
                switch (t.type) {
                  case "button":
                  case "input":
                  case "select":
                  case "textarea":
                    a.autoFocus && n.focus();
                    break;
                  case "img":
                    a.src && (n.src = a.src);
                }
              }
              break;
            case 6:
              break;
            case 4:
              break;
            case 12:
              break;
            case 13:
              if (t.memoizedState === null) {
                var g = t.alternate;
                if (g !== null) {
                  var E = g.memoizedState;
                  if (E !== null) {
                    var _ = E.dehydrated;
                    _ !== null && Hr(_);
                  }
                }
              }
              break;
            case 19:
            case 17:
            case 21:
            case 22:
            case 23:
            case 25:
              break;
            default:
              throw Error(f(163));
          }
          st || t.flags & 512 && Ko(t);
        } catch (S) {
          Ue(t, t.return, S);
        }
      }
      if (t === e) {
        F = null;
        break;
      }
      if (n = t.sibling, n !== null) {
        n.return = t.return, F = n;
        break;
      }
      F = t.return;
    }
  }
  function La(e) {
    for (; F !== null; ) {
      var t = F;
      if (t === e) {
        F = null;
        break;
      }
      var n = t.sibling;
      if (n !== null) {
        n.return = t.return, F = n;
        break;
      }
      F = t.return;
    }
  }
  function Pa(e) {
    for (; F !== null; ) {
      var t = F;
      try {
        switch (t.tag) {
          case 0:
          case 11:
          case 15:
            var n = t.return;
            try {
              ci(4, t);
            } catch (a) {
              Ue(t, n, a);
            }
            break;
          case 1:
            var r = t.stateNode;
            if (typeof r.componentDidMount == "function") {
              var l = t.return;
              try {
                r.componentDidMount();
              } catch (a) {
                Ue(t, l, a);
              }
            }
            var i = t.return;
            try {
              Ko(t);
            } catch (a) {
              Ue(t, i, a);
            }
            break;
          case 5:
            var o = t.return;
            try {
              Ko(t);
            } catch (a) {
              Ue(t, o, a);
            }
        }
      } catch (a) {
        Ue(t, t.return, a);
      }
      if (t === e) {
        F = null;
        break;
      }
      var s = t.sibling;
      if (s !== null) {
        s.return = t.return, F = s;
        break;
      }
      F = t.return;
    }
  }
  var Wf = Math.ceil, fi = ve.ReactCurrentDispatcher, Go = ve.ReactCurrentOwner, Ot = ve.ReactCurrentBatchConfig, pe = 0, qe = null, He = null, lt = 0, Lt = 0, Nr = Ln(0), Ke = 0, dl = null, Zn = 0, di = 0, Zo = 0, pl = null, xt = null, qo = 0, jr = 1 / 0, gn = null, pi = !1, Jo = null, In = null, hi = !1, Fn = null, mi = 0, hl = 0, bo = null, vi = -1, yi = 0;
  function ft() {
    return (pe & 6) !== 0 ? $e() : vi !== -1 ? vi : vi = $e();
  }
  function An(e) {
    return (e.mode & 1) === 0 ? 1 : (pe & 2) !== 0 && lt !== 0 ? lt & -lt : _f.transition !== null ? (yi === 0 && (yi = Eu()), yi) : (e = ge, e !== 0 || (e = window.event, e = e === void 0 ? 16 : Tu(e.type)), e);
  }
  function Kt(e, t, n, r) {
    if (50 < hl) throw hl = 0, bo = null, Error(f(185));
    Dr(e, n, r), ((pe & 2) === 0 || e !== qe) && (e === qe && ((pe & 2) === 0 && (di |= n), Ke === 4 && Dn(e, lt)), kt(e, r), n === 1 && pe === 0 && (t.mode & 1) === 0 && (jr = $e() + 500, Ql && Rn()));
  }
  function kt(e, t) {
    var n = e.callbackNode;
    Ec(e, t);
    var r = Nl(e, e === qe ? lt : 0);
    if (r === 0) n !== null && ye(n), e.callbackNode = null, e.callbackPriority = 0;
    else if (t = r & -r, e.callbackPriority !== t) {
      if (n != null && ye(n), t === 1) e.tag === 0 ? Ef(Ta.bind(null, e)) : ys(Ta.bind(null, e)), wf(function() {
        (pe & 6) === 0 && Rn();
      }), n = null;
      else {
        switch (_u(r)) {
          case 1:
            n = Ri;
            break;
          case 4:
            n = ku;
            break;
          case 16:
            n = Sl;
            break;
          case 536870912:
            n = Su;
            break;
          default:
            n = Sl;
        }
        n = $a(n, Ra.bind(null, e));
      }
      e.callbackPriority = t, e.callbackNode = n;
    }
  }
  function Ra(e, t) {
    if (vi = -1, yi = 0, (pe & 6) !== 0) throw Error(f(327));
    var n = e.callbackNode;
    if (zr() && e.callbackNode !== n) return null;
    var r = Nl(e, e === qe ? lt : 0);
    if (r === 0) return null;
    if ((r & 30) !== 0 || (r & e.expiredLanes) !== 0 || t) t = gi(e, r);
    else {
      t = r;
      var l = pe;
      pe |= 2;
      var i = Oa();
      (qe !== e || lt !== t) && (gn = null, jr = $e() + 500, Jn(e, t));
      do
        try {
          Vf();
          break;
        } catch (s) {
          Ma(e, s);
        }
      while (!0);
      yo(), fi.current = i, pe = l, He !== null ? t = 0 : (qe = null, lt = 0, t = Ke);
    }
    if (t !== 0) {
      if (t === 2 && (l = Ti(e), l !== 0 && (r = l, t = eu(e, l))), t === 1) throw n = dl, Jn(e, 0), Dn(e, r), kt(e, $e()), n;
      if (t === 6) Dn(e, r);
      else {
        if (l = e.current.alternate, (r & 30) === 0 && !Bf(l) && (t = gi(e, r), t === 2 && (i = Ti(e), i !== 0 && (r = i, t = eu(e, i))), t === 1)) throw n = dl, Jn(e, 0), Dn(e, r), kt(e, $e()), n;
        switch (e.finishedWork = l, e.finishedLanes = r, t) {
          case 0:
          case 1:
            throw Error(f(345));
          case 2:
            bn(e, xt, gn);
            break;
          case 3:
            if (Dn(e, r), (r & 130023424) === r && (t = qo + 500 - $e(), 10 < t)) {
              if (Nl(e, 0) !== 0) break;
              if (l = e.suspendedLanes, (l & r) !== r) {
                ft(), e.pingedLanes |= e.suspendedLanes & l;
                break;
              }
              e.timeoutHandle = io(bn.bind(null, e, xt, gn), t);
              break;
            }
            bn(e, xt, gn);
            break;
          case 4:
            if (Dn(e, r), (r & 4194240) === r) break;
            for (t = e.eventTimes, l = -1; 0 < r; ) {
              var o = 31 - $t(r);
              i = 1 << o, o = t[o], o > l && (l = o), r &= ~i;
            }
            if (r = l, r = $e() - r, r = (120 > r ? 120 : 480 > r ? 480 : 1080 > r ? 1080 : 1920 > r ? 1920 : 3e3 > r ? 3e3 : 4320 > r ? 4320 : 1960 * Wf(r / 1960)) - r, 10 < r) {
              e.timeoutHandle = io(bn.bind(null, e, xt, gn), r);
              break;
            }
            bn(e, xt, gn);
            break;
          case 5:
            bn(e, xt, gn);
            break;
          default:
            throw Error(f(329));
        }
      }
    }
    return kt(e, $e()), e.callbackNode === n ? Ra.bind(null, e) : null;
  }
  function eu(e, t) {
    var n = pl;
    return e.current.memoizedState.isDehydrated && (Jn(e, t).flags |= 256), e = gi(e, t), e !== 2 && (t = xt, xt = n, t !== null && tu(t)), e;
  }
  function tu(e) {
    xt === null ? xt = e : xt.push.apply(xt, e);
  }
  function Bf(e) {
    for (var t = e; ; ) {
      if (t.flags & 16384) {
        var n = t.updateQueue;
        if (n !== null && (n = n.stores, n !== null)) for (var r = 0; r < n.length; r++) {
          var l = n[r], i = l.getSnapshot;
          l = l.value;
          try {
            if (!Wt(i(), l)) return !1;
          } catch {
            return !1;
          }
        }
      }
      if (n = t.child, t.subtreeFlags & 16384 && n !== null) n.return = t, t = n;
      else {
        if (t === e) break;
        for (; t.sibling === null; ) {
          if (t.return === null || t.return === e) return !0;
          t = t.return;
        }
        t.sibling.return = t.return, t = t.sibling;
      }
    }
    return !0;
  }
  function Dn(e, t) {
    for (t &= ~Zo, t &= ~di, e.suspendedLanes |= t, e.pingedLanes &= ~t, e = e.expirationTimes; 0 < t; ) {
      var n = 31 - $t(t), r = 1 << n;
      e[n] = -1, t &= ~r;
    }
  }
  function Ta(e) {
    if ((pe & 6) !== 0) throw Error(f(327));
    zr();
    var t = Nl(e, 0);
    if ((t & 1) === 0) return kt(e, $e()), null;
    var n = gi(e, t);
    if (e.tag !== 0 && n === 2) {
      var r = Ti(e);
      r !== 0 && (t = r, n = eu(e, r));
    }
    if (n === 1) throw n = dl, Jn(e, 0), Dn(e, t), kt(e, $e()), n;
    if (n === 6) throw Error(f(345));
    return e.finishedWork = e.current.alternate, e.finishedLanes = t, bn(e, xt, gn), kt(e, $e()), null;
  }
  function nu(e, t) {
    var n = pe;
    pe |= 1;
    try {
      return e(t);
    } finally {
      pe = n, pe === 0 && (jr = $e() + 500, Ql && Rn());
    }
  }
  function qn(e) {
    Fn !== null && Fn.tag === 0 && (pe & 6) === 0 && zr();
    var t = pe;
    pe |= 1;
    var n = Ot.transition, r = ge;
    try {
      if (Ot.transition = null, ge = 1, e) return e();
    } finally {
      ge = r, Ot.transition = n, pe = t, (pe & 6) === 0 && Rn();
    }
  }
  function ru() {
    Lt = Nr.current, Pe(Nr);
  }
  function Jn(e, t) {
    e.finishedWork = null, e.finishedLanes = 0;
    var n = e.timeoutHandle;
    if (n !== -1 && (e.timeoutHandle = -1, gf(n)), He !== null) for (n = He.return; n !== null; ) {
      var r = n;
      switch (fo(r), r.tag) {
        case 1:
          r = r.type.childContextTypes, r != null && Hl();
          break;
        case 3:
          Er(), Pe(yt), Pe(it), Co();
          break;
        case 5:
          Eo(r);
          break;
        case 4:
          Er();
          break;
        case 13:
          Pe(Fe);
          break;
        case 19:
          Pe(Fe);
          break;
        case 10:
          go(r.type._context);
          break;
        case 22:
        case 23:
          ru();
      }
      n = n.return;
    }
    if (qe = e, He = e = Un(e.current, null), lt = Lt = t, Ke = 0, dl = null, Zo = di = Zn = 0, xt = pl = null, Yn !== null) {
      for (t = 0; t < Yn.length; t++) if (n = Yn[t], r = n.interleaved, r !== null) {
        n.interleaved = null;
        var l = r.next, i = n.pending;
        if (i !== null) {
          var o = i.next;
          i.next = l, r.next = o;
        }
        n.pending = r;
      }
      Yn = null;
    }
    return e;
  }
  function Ma(e, t) {
    do {
      var n = He;
      try {
        if (yo(), ti.current = ii, ni) {
          for (var r = Ae.memoizedState; r !== null; ) {
            var l = r.queue;
            l !== null && (l.pending = null), r = r.next;
          }
          ni = !1;
        }
        if (Gn = 0, Ze = Qe = Ae = null, ol = !1, ul = 0, Go.current = null, n === null || n.return === null) {
          Ke = 1, dl = t, He = null;
          break;
        }
        e: {
          var i = e, o = n.return, s = n, a = t;
          if (t = lt, s.flags |= 32768, a !== null && typeof a == "object" && typeof a.then == "function") {
            var g = a, E = s, _ = E.tag;
            if ((E.mode & 1) === 0 && (_ === 0 || _ === 11 || _ === 15)) {
              var S = E.alternate;
              S ? (E.updateQueue = S.updateQueue, E.memoizedState = S.memoizedState, E.lanes = S.lanes) : (E.updateQueue = null, E.memoizedState = null);
            }
            var M = la(o);
            if (M !== null) {
              M.flags &= -257, ia(M, o, s, i, t), M.mode & 1 && ra(i, g, t), t = M, a = g;
              var A = t.updateQueue;
              if (A === null) {
                var U = /* @__PURE__ */ new Set();
                U.add(a), t.updateQueue = U;
              } else A.add(a);
              break e;
            } else {
              if ((t & 1) === 0) {
                ra(i, g, t), lu();
                break e;
              }
              a = Error(f(426));
            }
          } else if (Te && s.mode & 1) {
            var We = la(o);
            if (We !== null) {
              (We.flags & 65536) === 0 && (We.flags |= 256), ia(We, o, s, i, t), mo(_r(a, s));
              break e;
            }
          }
          i = a = _r(a, s), Ke !== 4 && (Ke = 2), pl === null ? pl = [i] : pl.push(i), i = o;
          do {
            switch (i.tag) {
              case 3:
                i.flags |= 65536, t &= -t, i.lanes |= t;
                var h = ta(i, a, t);
                zs(i, h);
                break e;
              case 1:
                s = a;
                var p = i.type, v = i.stateNode;
                if ((i.flags & 128) === 0 && (typeof p.getDerivedStateFromError == "function" || v !== null && typeof v.componentDidCatch == "function" && (In === null || !In.has(v)))) {
                  i.flags |= 65536, t &= -t, i.lanes |= t;
                  var z = na(i, s, t);
                  zs(i, z);
                  break e;
                }
            }
            i = i.return;
          } while (i !== null);
        }
        Fa(n);
      } catch (B) {
        t = B, He === n && n !== null && (He = n = n.return);
        continue;
      }
      break;
    } while (!0);
  }
  function Oa() {
    var e = fi.current;
    return fi.current = ii, e === null ? ii : e;
  }
  function lu() {
    (Ke === 0 || Ke === 3 || Ke === 2) && (Ke = 4), qe === null || (Zn & 268435455) === 0 && (di & 268435455) === 0 || Dn(qe, lt);
  }
  function gi(e, t) {
    var n = pe;
    pe |= 2;
    var r = Oa();
    (qe !== e || lt !== t) && (gn = null, Jn(e, t));
    do
      try {
        Hf();
        break;
      } catch (l) {
        Ma(e, l);
      }
    while (!0);
    if (yo(), pe = n, fi.current = r, He !== null) throw Error(f(261));
    return qe = null, lt = 0, Ke;
  }
  function Hf() {
    for (; He !== null; ) Ia(He);
  }
  function Vf() {
    for (; He !== null && !vt(); ) Ia(He);
  }
  function Ia(e) {
    var t = Ua(e.alternate, e, Lt);
    e.memoizedProps = e.pendingProps, t === null ? Fa(e) : He = t, Go.current = null;
  }
  function Fa(e) {
    var t = e;
    do {
      var n = t.alternate;
      if (e = t.return, (t.flags & 32768) === 0) {
        if (n = Ff(n, t, Lt), n !== null) {
          He = n;
          return;
        }
      } else {
        if (n = Af(n, t), n !== null) {
          n.flags &= 32767, He = n;
          return;
        }
        if (e !== null) e.flags |= 32768, e.subtreeFlags = 0, e.deletions = null;
        else {
          Ke = 6, He = null;
          return;
        }
      }
      if (t = t.sibling, t !== null) {
        He = t;
        return;
      }
      He = t = e;
    } while (t !== null);
    Ke === 0 && (Ke = 5);
  }
  function bn(e, t, n) {
    var r = ge, l = Ot.transition;
    try {
      Ot.transition = null, ge = 1, Qf(e, t, n, r);
    } finally {
      Ot.transition = l, ge = r;
    }
    return null;
  }
  function Qf(e, t, n, r) {
    do
      zr();
    while (Fn !== null);
    if ((pe & 6) !== 0) throw Error(f(327));
    n = e.finishedWork;
    var l = e.finishedLanes;
    if (n === null) return null;
    if (e.finishedWork = null, e.finishedLanes = 0, n === e.current) throw Error(f(177));
    e.callbackNode = null, e.callbackPriority = 0;
    var i = n.lanes | n.childLanes;
    if (_c(e, i), e === qe && (He = qe = null, lt = 0), (n.subtreeFlags & 2064) === 0 && (n.flags & 2064) === 0 || hi || (hi = !0, $a(Sl, function() {
      return zr(), null;
    })), i = (n.flags & 15990) !== 0, (n.subtreeFlags & 15990) !== 0 || i) {
      i = Ot.transition, Ot.transition = null;
      var o = ge;
      ge = 1;
      var s = pe;
      pe |= 4, Go.current = null, Uf(e, n), Na(n, e), ff(ro), Ll = !!no, ro = no = null, e.current = n, $f(n), cn(), pe = s, ge = o, Ot.transition = i;
    } else e.current = n;
    if (hi && (hi = !1, Fn = e, mi = l), i = e.pendingLanes, i === 0 && (In = null), gc(n.stateNode), kt(e, $e()), t !== null) for (r = e.onRecoverableError, n = 0; n < t.length; n++) l = t[n], r(l.value, { componentStack: l.stack, digest: l.digest });
    if (pi) throw pi = !1, e = Jo, Jo = null, e;
    return (mi & 1) !== 0 && e.tag !== 0 && zr(), i = e.pendingLanes, (i & 1) !== 0 ? e === bo ? hl++ : (hl = 0, bo = e) : hl = 0, Rn(), null;
  }
  function zr() {
    if (Fn !== null) {
      var e = _u(mi), t = Ot.transition, n = ge;
      try {
        if (Ot.transition = null, ge = 16 > e ? 16 : e, Fn === null) var r = !1;
        else {
          if (e = Fn, Fn = null, mi = 0, (pe & 6) !== 0) throw Error(f(331));
          var l = pe;
          for (pe |= 4, F = e.current; F !== null; ) {
            var i = F, o = i.child;
            if ((F.flags & 16) !== 0) {
              var s = i.deletions;
              if (s !== null) {
                for (var a = 0; a < s.length; a++) {
                  var g = s[a];
                  for (F = g; F !== null; ) {
                    var E = F;
                    switch (E.tag) {
                      case 0:
                      case 11:
                      case 15:
                        fl(8, E, i);
                    }
                    var _ = E.child;
                    if (_ !== null) _.return = E, F = _;
                    else for (; F !== null; ) {
                      E = F;
                      var S = E.sibling, M = E.return;
                      if (ka(E), E === g) {
                        F = null;
                        break;
                      }
                      if (S !== null) {
                        S.return = M, F = S;
                        break;
                      }
                      F = M;
                    }
                  }
                }
                var A = i.alternate;
                if (A !== null) {
                  var U = A.child;
                  if (U !== null) {
                    A.child = null;
                    do {
                      var We = U.sibling;
                      U.sibling = null, U = We;
                    } while (U !== null);
                  }
                }
                F = i;
              }
            }
            if ((i.subtreeFlags & 2064) !== 0 && o !== null) o.return = i, F = o;
            else e: for (; F !== null; ) {
              if (i = F, (i.flags & 2048) !== 0) switch (i.tag) {
                case 0:
                case 11:
                case 15:
                  fl(9, i, i.return);
              }
              var h = i.sibling;
              if (h !== null) {
                h.return = i.return, F = h;
                break e;
              }
              F = i.return;
            }
          }
          var p = e.current;
          for (F = p; F !== null; ) {
            o = F;
            var v = o.child;
            if ((o.subtreeFlags & 2064) !== 0 && v !== null) v.return = o, F = v;
            else e: for (o = p; F !== null; ) {
              if (s = F, (s.flags & 2048) !== 0) try {
                switch (s.tag) {
                  case 0:
                  case 11:
                  case 15:
                    ci(9, s);
                }
              } catch (B) {
                Ue(s, s.return, B);
              }
              if (s === o) {
                F = null;
                break e;
              }
              var z = s.sibling;
              if (z !== null) {
                z.return = s.return, F = z;
                break e;
              }
              F = s.return;
            }
          }
          if (pe = l, Rn(), qt && typeof qt.onPostCommitFiberRoot == "function") try {
            qt.onPostCommitFiberRoot(El, e);
          } catch {
          }
          r = !0;
        }
        return r;
      } finally {
        ge = n, Ot.transition = t;
      }
    }
    return !1;
  }
  function Aa(e, t, n) {
    t = _r(n, t), t = ta(e, t, 1), e = Mn(e, t, 1), t = ft(), e !== null && (Dr(e, 1, t), kt(e, t));
  }
  function Ue(e, t, n) {
    if (e.tag === 3) Aa(e, e, n);
    else for (; t !== null; ) {
      if (t.tag === 3) {
        Aa(t, e, n);
        break;
      } else if (t.tag === 1) {
        var r = t.stateNode;
        if (typeof t.type.getDerivedStateFromError == "function" || typeof r.componentDidCatch == "function" && (In === null || !In.has(r))) {
          e = _r(n, e), e = na(t, e, 1), t = Mn(t, e, 1), e = ft(), t !== null && (Dr(t, 1, e), kt(t, e));
          break;
        }
      }
      t = t.return;
    }
  }
  function Kf(e, t, n) {
    var r = e.pingCache;
    r !== null && r.delete(t), t = ft(), e.pingedLanes |= e.suspendedLanes & n, qe === e && (lt & n) === n && (Ke === 4 || Ke === 3 && (lt & 130023424) === lt && 500 > $e() - qo ? Jn(e, 0) : Zo |= n), kt(e, t);
  }
  function Da(e, t) {
    t === 0 && ((e.mode & 1) === 0 ? t = 1 : (t = Cl, Cl <<= 1, (Cl & 130023424) === 0 && (Cl = 4194304)));
    var n = ft();
    e = mn(e, t), e !== null && (Dr(e, t, n), kt(e, n));
  }
  function Yf(e) {
    var t = e.memoizedState, n = 0;
    t !== null && (n = t.retryLane), Da(e, n);
  }
  function Xf(e, t) {
    var n = 0;
    switch (e.tag) {
      case 13:
        var r = e.stateNode, l = e.memoizedState;
        l !== null && (n = l.retryLane);
        break;
      case 19:
        r = e.stateNode;
        break;
      default:
        throw Error(f(314));
    }
    r !== null && r.delete(t), Da(e, n);
  }
  var Ua;
  Ua = function(e, t, n) {
    if (e !== null) if (e.memoizedProps !== t.pendingProps || yt.current) wt = !0;
    else {
      if ((e.lanes & n) === 0 && (t.flags & 128) === 0) return wt = !1, If(e, t, n);
      wt = (e.flags & 131072) !== 0;
    }
    else wt = !1, Te && (t.flags & 1048576) !== 0 && gs(t, Yl, t.index);
    switch (t.lanes = 0, t.tag) {
      case 2:
        var r = t.type;
        si(e, t), e = t.pendingProps;
        var l = vr(t, it.current);
        Sr(t, n), l = zo(null, t, r, e, l, n);
        var i = Lo();
        return t.flags |= 1, typeof l == "object" && l !== null && typeof l.render == "function" && l.$$typeof === void 0 ? (t.tag = 1, t.memoizedState = null, t.updateQueue = null, gt(r) ? (i = !0, Vl(t)) : i = !1, t.memoizedState = l.state !== null && l.state !== void 0 ? l.state : null, ko(t), l.updater = oi, t.stateNode = l, l._reactInternals = t, Io(t, r, e, n), t = Uo(null, t, r, !0, i, n)) : (t.tag = 0, Te && i && co(t), ct(null, t, l, n), t = t.child), t;
      case 16:
        r = t.elementType;
        e: {
          switch (si(e, t), e = t.pendingProps, l = r._init, r = l(r._payload), t.type = r, l = t.tag = Zf(r), e = Ht(r, e), l) {
            case 0:
              t = Do(null, t, r, e, n);
              break e;
            case 1:
              t = fa(null, t, r, e, n);
              break e;
            case 11:
              t = oa(null, t, r, e, n);
              break e;
            case 14:
              t = ua(null, t, r, Ht(r.type, e), n);
              break e;
          }
          throw Error(f(
            306,
            r,
            ""
          ));
        }
        return t;
      case 0:
        return r = t.type, l = t.pendingProps, l = t.elementType === r ? l : Ht(r, l), Do(e, t, r, l, n);
      case 1:
        return r = t.type, l = t.pendingProps, l = t.elementType === r ? l : Ht(r, l), fa(e, t, r, l, n);
      case 3:
        e: {
          if (da(t), e === null) throw Error(f(387));
          r = t.pendingProps, i = t.memoizedState, l = i.element, js(e, t), bl(t, r, null, n);
          var o = t.memoizedState;
          if (r = o.element, i.isDehydrated) if (i = { element: r, isDehydrated: !1, cache: o.cache, pendingSuspenseBoundaries: o.pendingSuspenseBoundaries, transitions: o.transitions }, t.updateQueue.baseState = i, t.memoizedState = i, t.flags & 256) {
            l = _r(Error(f(423)), t), t = pa(e, t, r, n, l);
            break e;
          } else if (r !== l) {
            l = _r(Error(f(424)), t), t = pa(e, t, r, n, l);
            break e;
          } else for (zt = zn(t.stateNode.containerInfo.firstChild), jt = t, Te = !0, Bt = null, n = Cs(t, null, r, n), t.child = n; n; ) n.flags = n.flags & -3 | 4096, n = n.sibling;
          else {
            if (wr(), r === l) {
              t = yn(e, t, n);
              break e;
            }
            ct(e, t, r, n);
          }
          t = t.child;
        }
        return t;
      case 5:
        return Ps(t), e === null && ho(t), r = t.type, l = t.pendingProps, i = e !== null ? e.memoizedProps : null, o = l.children, lo(r, l) ? o = null : i !== null && lo(r, i) && (t.flags |= 32), ca(e, t), ct(e, t, o, n), t.child;
      case 6:
        return e === null && ho(t), null;
      case 13:
        return ha(e, t, n);
      case 4:
        return So(t, t.stateNode.containerInfo), r = t.pendingProps, e === null ? t.child = xr(t, null, r, n) : ct(e, t, r, n), t.child;
      case 11:
        return r = t.type, l = t.pendingProps, l = t.elementType === r ? l : Ht(r, l), oa(e, t, r, l, n);
      case 7:
        return ct(e, t, t.pendingProps, n), t.child;
      case 8:
        return ct(e, t, t.pendingProps.children, n), t.child;
      case 12:
        return ct(e, t, t.pendingProps.children, n), t.child;
      case 10:
        e: {
          if (r = t.type._context, l = t.pendingProps, i = t.memoizedProps, o = l.value, Ce(Zl, r._currentValue), r._currentValue = o, i !== null) if (Wt(i.value, o)) {
            if (i.children === l.children && !yt.current) {
              t = yn(e, t, n);
              break e;
            }
          } else for (i = t.child, i !== null && (i.return = t); i !== null; ) {
            var s = i.dependencies;
            if (s !== null) {
              o = i.child;
              for (var a = s.firstContext; a !== null; ) {
                if (a.context === r) {
                  if (i.tag === 1) {
                    a = vn(-1, n & -n), a.tag = 2;
                    var g = i.updateQueue;
                    if (g !== null) {
                      g = g.shared;
                      var E = g.pending;
                      E === null ? a.next = a : (a.next = E.next, E.next = a), g.pending = a;
                    }
                  }
                  i.lanes |= n, a = i.alternate, a !== null && (a.lanes |= n), wo(
                    i.return,
                    n,
                    t
                  ), s.lanes |= n;
                  break;
                }
                a = a.next;
              }
            } else if (i.tag === 10) o = i.type === t.type ? null : i.child;
            else if (i.tag === 18) {
              if (o = i.return, o === null) throw Error(f(341));
              o.lanes |= n, s = o.alternate, s !== null && (s.lanes |= n), wo(o, n, t), o = i.sibling;
            } else o = i.child;
            if (o !== null) o.return = i;
            else for (o = i; o !== null; ) {
              if (o === t) {
                o = null;
                break;
              }
              if (i = o.sibling, i !== null) {
                i.return = o.return, o = i;
                break;
              }
              o = o.return;
            }
            i = o;
          }
          ct(e, t, l.children, n), t = t.child;
        }
        return t;
      case 9:
        return l = t.type, r = t.pendingProps.children, Sr(t, n), l = Tt(l), r = r(l), t.flags |= 1, ct(e, t, r, n), t.child;
      case 14:
        return r = t.type, l = Ht(r, t.pendingProps), l = Ht(r.type, l), ua(e, t, r, l, n);
      case 15:
        return sa(e, t, t.type, t.pendingProps, n);
      case 17:
        return r = t.type, l = t.pendingProps, l = t.elementType === r ? l : Ht(r, l), si(e, t), t.tag = 1, gt(r) ? (e = !0, Vl(t)) : e = !1, Sr(t, n), bs(t, r, l), Io(t, r, l, n), Uo(null, t, r, !0, e, n);
      case 19:
        return va(e, t, n);
      case 22:
        return aa(e, t, n);
    }
    throw Error(f(156, t.tag));
  };
  function $a(e, t) {
    return Fr(e, t);
  }
  function Gf(e, t, n, r) {
    this.tag = e, this.key = n, this.sibling = this.child = this.return = this.stateNode = this.type = this.elementType = null, this.index = 0, this.ref = null, this.pendingProps = t, this.dependencies = this.memoizedState = this.updateQueue = this.memoizedProps = null, this.mode = r, this.subtreeFlags = this.flags = 0, this.deletions = null, this.childLanes = this.lanes = 0, this.alternate = null;
  }
  function It(e, t, n, r) {
    return new Gf(e, t, n, r);
  }
  function iu(e) {
    return e = e.prototype, !(!e || !e.isReactComponent);
  }
  function Zf(e) {
    if (typeof e == "function") return iu(e) ? 1 : 0;
    if (e != null) {
      if (e = e.$$typeof, e === be) return 11;
      if (e === Xe) return 14;
    }
    return 2;
  }
  function Un(e, t) {
    var n = e.alternate;
    return n === null ? (n = It(e.tag, t, e.key, e.mode), n.elementType = e.elementType, n.type = e.type, n.stateNode = e.stateNode, n.alternate = e, e.alternate = n) : (n.pendingProps = t, n.type = e.type, n.flags = 0, n.subtreeFlags = 0, n.deletions = null), n.flags = e.flags & 14680064, n.childLanes = e.childLanes, n.lanes = e.lanes, n.child = e.child, n.memoizedProps = e.memoizedProps, n.memoizedState = e.memoizedState, n.updateQueue = e.updateQueue, t = e.dependencies, n.dependencies = t === null ? null : { lanes: t.lanes, firstContext: t.firstContext }, n.sibling = e.sibling, n.index = e.index, n.ref = e.ref, n;
  }
  function wi(e, t, n, r, l, i) {
    var o = 2;
    if (r = e, typeof e == "function") iu(e) && (o = 1);
    else if (typeof e == "string") o = 5;
    else e: switch (e) {
      case je:
        return er(n.children, l, i, t);
      case D:
        o = 8, l |= 8;
        break;
      case Et:
        return e = It(12, n, t, l | 2), e.elementType = Et, e.lanes = i, e;
      case Be:
        return e = It(13, n, t, l), e.elementType = Be, e.lanes = i, e;
      case Ye:
        return e = It(19, n, t, l), e.elementType = Ye, e.lanes = i, e;
      case le:
        return xi(n, l, i, t);
      default:
        if (typeof e == "object" && e !== null) switch (e.$$typeof) {
          case De:
            o = 10;
            break e;
          case xe:
            o = 9;
            break e;
          case be:
            o = 11;
            break e;
          case Xe:
            o = 14;
            break e;
          case ze:
            o = 16, r = null;
            break e;
        }
        throw Error(f(130, e == null ? e : typeof e, ""));
    }
    return t = It(o, n, t, l), t.elementType = e, t.type = r, t.lanes = i, t;
  }
  function er(e, t, n, r) {
    return e = It(7, e, r, t), e.lanes = n, e;
  }
  function xi(e, t, n, r) {
    return e = It(22, e, r, t), e.elementType = le, e.lanes = n, e.stateNode = { isHidden: !1 }, e;
  }
  function ou(e, t, n) {
    return e = It(6, e, null, t), e.lanes = n, e;
  }
  function uu(e, t, n) {
    return t = It(4, e.children !== null ? e.children : [], e.key, t), t.lanes = n, t.stateNode = { containerInfo: e.containerInfo, pendingChildren: null, implementation: e.implementation }, t;
  }
  function qf(e, t, n, r, l) {
    this.tag = t, this.containerInfo = e, this.finishedWork = this.pingCache = this.current = this.pendingChildren = null, this.timeoutHandle = -1, this.callbackNode = this.pendingContext = this.context = null, this.callbackPriority = 0, this.eventTimes = Mi(0), this.expirationTimes = Mi(-1), this.entangledLanes = this.finishedLanes = this.mutableReadLanes = this.expiredLanes = this.pingedLanes = this.suspendedLanes = this.pendingLanes = 0, this.entanglements = Mi(0), this.identifierPrefix = r, this.onRecoverableError = l, this.mutableSourceEagerHydrationData = null;
  }
  function su(e, t, n, r, l, i, o, s, a) {
    return e = new qf(e, t, n, s, a), t === 1 ? (t = 1, i === !0 && (t |= 8)) : t = 0, i = It(3, null, null, t), e.current = i, i.stateNode = e, i.memoizedState = { element: r, isDehydrated: n, cache: null, transitions: null, pendingSuspenseBoundaries: null }, ko(i), e;
  }
  function Jf(e, t, n) {
    var r = 3 < arguments.length && arguments[3] !== void 0 ? arguments[3] : null;
    return { $$typeof: Ie, key: r == null ? null : "" + r, children: e, containerInfo: t, implementation: n };
  }
  function Wa(e) {
    if (!e) return Pn;
    e = e._reactInternals;
    e: {
      if (mt(e) !== e || e.tag !== 1) throw Error(f(170));
      var t = e;
      do {
        switch (t.tag) {
          case 3:
            t = t.stateNode.context;
            break e;
          case 1:
            if (gt(t.type)) {
              t = t.stateNode.__reactInternalMemoizedMergedChildContext;
              break e;
            }
        }
        t = t.return;
      } while (t !== null);
      throw Error(f(171));
    }
    if (e.tag === 1) {
      var n = e.type;
      if (gt(n)) return ms(e, n, t);
    }
    return t;
  }
  function Ba(e, t, n, r, l, i, o, s, a) {
    return e = su(n, r, !0, e, l, i, o, s, a), e.context = Wa(null), n = e.current, r = ft(), l = An(n), i = vn(r, l), i.callback = t ?? null, Mn(n, i, l), e.current.lanes = l, Dr(e, l, r), kt(e, r), e;
  }
  function ki(e, t, n, r) {
    var l = t.current, i = ft(), o = An(l);
    return n = Wa(n), t.context === null ? t.context = n : t.pendingContext = n, t = vn(i, o), t.payload = { element: e }, r = r === void 0 ? null : r, r !== null && (t.callback = r), e = Mn(l, t, o), e !== null && (Kt(e, l, o, i), Jl(e, l, o)), o;
  }
  function Si(e) {
    if (e = e.current, !e.child) return null;
    switch (e.child.tag) {
      case 5:
        return e.child.stateNode;
      default:
        return e.child.stateNode;
    }
  }
  function Ha(e, t) {
    if (e = e.memoizedState, e !== null && e.dehydrated !== null) {
      var n = e.retryLane;
      e.retryLane = n !== 0 && n < t ? n : t;
    }
  }
  function au(e, t) {
    Ha(e, t), (e = e.alternate) && Ha(e, t);
  }
  function bf() {
    return null;
  }
  var Va = typeof reportError == "function" ? reportError : function(e) {
    console.error(e);
  };
  function cu(e) {
    this._internalRoot = e;
  }
  Ei.prototype.render = cu.prototype.render = function(e) {
    var t = this._internalRoot;
    if (t === null) throw Error(f(409));
    ki(e, t, null, null);
  }, Ei.prototype.unmount = cu.prototype.unmount = function() {
    var e = this._internalRoot;
    if (e !== null) {
      this._internalRoot = null;
      var t = e.containerInfo;
      qn(function() {
        ki(null, e, null, null);
      }), t[fn] = null;
    }
  };
  function Ei(e) {
    this._internalRoot = e;
  }
  Ei.prototype.unstable_scheduleHydration = function(e) {
    if (e) {
      var t = ju();
      e = { blockedOn: null, target: e, priority: t };
      for (var n = 0; n < Cn.length && t !== 0 && t < Cn[n].priority; n++) ;
      Cn.splice(n, 0, e), n === 0 && Pu(e);
    }
  };
  function fu(e) {
    return !(!e || e.nodeType !== 1 && e.nodeType !== 9 && e.nodeType !== 11);
  }
  function _i(e) {
    return !(!e || e.nodeType !== 1 && e.nodeType !== 9 && e.nodeType !== 11 && (e.nodeType !== 8 || e.nodeValue !== " react-mount-point-unstable "));
  }
  function Qa() {
  }
  function ed(e, t, n, r, l) {
    if (l) {
      if (typeof r == "function") {
        var i = r;
        r = function() {
          var g = Si(o);
          i.call(g);
        };
      }
      var o = Ba(t, r, e, 0, null, !1, !1, "", Qa);
      return e._reactRootContainer = o, e[fn] = o.current, Jr(e.nodeType === 8 ? e.parentNode : e), qn(), o;
    }
    for (; l = e.lastChild; ) e.removeChild(l);
    if (typeof r == "function") {
      var s = r;
      r = function() {
        var g = Si(a);
        s.call(g);
      };
    }
    var a = su(e, 0, !1, null, null, !1, !1, "", Qa);
    return e._reactRootContainer = a, e[fn] = a.current, Jr(e.nodeType === 8 ? e.parentNode : e), qn(function() {
      ki(t, a, n, r);
    }), a;
  }
  function Ci(e, t, n, r, l) {
    var i = n._reactRootContainer;
    if (i) {
      var o = i;
      if (typeof l == "function") {
        var s = l;
        l = function() {
          var a = Si(o);
          s.call(a);
        };
      }
      ki(t, o, e, l);
    } else o = ed(n, t, e, l, r);
    return Si(o);
  }
  Cu = function(e) {
    switch (e.tag) {
      case 3:
        var t = e.stateNode;
        if (t.current.memoizedState.isDehydrated) {
          var n = Ar(t.pendingLanes);
          n !== 0 && (Oi(t, n | 1), kt(t, $e()), (pe & 6) === 0 && (jr = $e() + 500, Rn()));
        }
        break;
      case 13:
        qn(function() {
          var r = mn(e, 1);
          if (r !== null) {
            var l = ft();
            Kt(r, e, 1, l);
          }
        }), au(e, 1);
    }
  }, Ii = function(e) {
    if (e.tag === 13) {
      var t = mn(e, 134217728);
      if (t !== null) {
        var n = ft();
        Kt(t, e, 134217728, n);
      }
      au(e, 134217728);
    }
  }, Nu = function(e) {
    if (e.tag === 13) {
      var t = An(e), n = mn(e, t);
      if (n !== null) {
        var r = ft();
        Kt(n, e, t, r);
      }
      au(e, t);
    }
  }, ju = function() {
    return ge;
  }, zu = function(e, t) {
    var n = ge;
    try {
      return ge = e, t();
    } finally {
      ge = n;
    }
  }, Bn = function(e, t, n) {
    switch (t) {
      case "input":
        if (Ee(e, n), t = n.name, n.type === "radio" && t != null) {
          for (n = e; n.parentNode; ) n = n.parentNode;
          for (n = n.querySelectorAll("input[name=" + JSON.stringify("" + t) + '][type="radio"]'), t = 0; t < n.length; t++) {
            var r = n[t];
            if (r !== e && r.form === e.form) {
              var l = Bl(r);
              if (!l) throw Error(f(90));
              ae(r), Ee(r, l);
            }
          }
        }
        break;
      case "textarea":
        At(e, n);
        break;
      case "select":
        t = n.value, t != null && dt(e, !!n.multiple, t, !1);
    }
  }, xl = nu, R = qn;
  var td = { usingClientEntryPoint: !1, Events: [tl, hr, Bl, Mr, wl, nu] }, ml = { findFiberByHostInstance: Hn, bundleType: 0, version: "18.3.1", rendererPackageName: "react-dom" }, nd = { bundleType: ml.bundleType, version: ml.version, rendererPackageName: ml.rendererPackageName, rendererConfig: ml.rendererConfig, overrideHookState: null, overrideHookStateDeletePath: null, overrideHookStateRenamePath: null, overrideProps: null, overridePropsDeletePath: null, overridePropsRenamePath: null, setErrorHandler: null, setSuspenseHandler: null, scheduleUpdate: null, currentDispatcherRef: ve.ReactCurrentDispatcher, findHostInstanceByFiber: function(e) {
    return e = Or(e), e === null ? null : e.stateNode;
  }, findFiberByHostInstance: ml.findFiberByHostInstance || bf, findHostInstancesForRefresh: null, scheduleRefresh: null, scheduleRoot: null, setRefreshHandler: null, getCurrentFiber: null, reconcilerVersion: "18.3.1-next-f1338f8080-20240426" };
  if (typeof __REACT_DEVTOOLS_GLOBAL_HOOK__ < "u") {
    var Ni = __REACT_DEVTOOLS_GLOBAL_HOOK__;
    if (!Ni.isDisabled && Ni.supportsFiber) try {
      El = Ni.inject(nd), qt = Ni;
    } catch {
    }
  }
  return St.__SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED = td, St.createPortal = function(e, t) {
    var n = 2 < arguments.length && arguments[2] !== void 0 ? arguments[2] : null;
    if (!fu(t)) throw Error(f(200));
    return Jf(e, t, null, n);
  }, St.createRoot = function(e, t) {
    if (!fu(e)) throw Error(f(299));
    var n = !1, r = "", l = Va;
    return t != null && (t.unstable_strictMode === !0 && (n = !0), t.identifierPrefix !== void 0 && (r = t.identifierPrefix), t.onRecoverableError !== void 0 && (l = t.onRecoverableError)), t = su(e, 1, !1, null, null, n, !1, r, l), e[fn] = t.current, Jr(e.nodeType === 8 ? e.parentNode : e), new cu(t);
  }, St.findDOMNode = function(e) {
    if (e == null) return null;
    if (e.nodeType === 1) return e;
    var t = e._reactInternals;
    if (t === void 0)
      throw typeof e.render == "function" ? Error(f(188)) : (e = Object.keys(e).join(","), Error(f(268, e)));
    return e = Or(t), e = e === null ? null : e.stateNode, e;
  }, St.flushSync = function(e) {
    return qn(e);
  }, St.hydrate = function(e, t, n) {
    if (!_i(t)) throw Error(f(200));
    return Ci(null, e, t, !0, n);
  }, St.hydrateRoot = function(e, t, n) {
    if (!fu(e)) throw Error(f(405));
    var r = n != null && n.hydratedSources || null, l = !1, i = "", o = Va;
    if (n != null && (n.unstable_strictMode === !0 && (l = !0), n.identifierPrefix !== void 0 && (i = n.identifierPrefix), n.onRecoverableError !== void 0 && (o = n.onRecoverableError)), t = Ba(t, null, e, 1, n ?? null, l, !1, i, o), e[fn] = t.current, Jr(e), r) for (e = 0; e < r.length; e++) n = r[e], l = n._getVersion, l = l(n._source), t.mutableSourceEagerHydrationData == null ? t.mutableSourceEagerHydrationData = [n, l] : t.mutableSourceEagerHydrationData.push(
      n,
      l
    );
    return new Ei(t);
  }, St.render = function(e, t, n) {
    if (!_i(t)) throw Error(f(200));
    return Ci(null, e, t, !1, n);
  }, St.unmountComponentAtNode = function(e) {
    if (!_i(e)) throw Error(f(40));
    return e._reactRootContainer ? (qn(function() {
      Ci(null, null, e, !1, function() {
        e._reactRootContainer = null, e[fn] = null;
      });
    }), !0) : !1;
  }, St.unstable_batchedUpdates = nu, St.unstable_renderSubtreeIntoContainer = function(e, t, n, r) {
    if (!_i(n)) throw Error(f(200));
    if (e == null || e._reactInternals === void 0) throw Error(f(38));
    return Ci(e, t, n, !1, r);
  }, St.version = "18.3.1-next-f1338f8080-20240426", St;
}
var ba;
function sc() {
  if (ba) return hu.exports;
  ba = 1;
  function d() {
    if (!(typeof __REACT_DEVTOOLS_GLOBAL_HOOK__ > "u" || typeof __REACT_DEVTOOLS_GLOBAL_HOOK__.checkDCE != "function"))
      try {
        __REACT_DEVTOOLS_GLOBAL_HOOK__.checkDCE(d);
      } catch (w) {
        console.error(w);
      }
  }
  return d(), hu.exports = ad(), hu.exports;
}
var ec;
function cd() {
  if (ec) return ji;
  ec = 1;
  var d = sc();
  return ji.createRoot = d.createRoot, ji.hydrateRoot = d.hydrateRoot, ji;
}
var fd = cd(), W = wu();
/**
 * @license lucide-react v0.468.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */
const dd = (d) => d.replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase(), ac = (...d) => d.filter((w, f, N) => !!w && w.trim() !== "" && N.indexOf(w) === f).join(" ").trim();
/**
 * @license lucide-react v0.468.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */
var pd = {
  xmlns: "http://www.w3.org/2000/svg",
  width: 24,
  height: 24,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 2,
  strokeLinecap: "round",
  strokeLinejoin: "round"
};
/**
 * @license lucide-react v0.468.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */
const hd = W.forwardRef(
  ({
    color: d = "currentColor",
    size: w = 24,
    strokeWidth: f = 2,
    absoluteStrokeWidth: N,
    className: j = "",
    children: C,
    iconNode: V,
    ...ee
  }, I) => W.createElement(
    "svg",
    {
      ref: I,
      ...pd,
      width: w,
      height: w,
      stroke: d,
      strokeWidth: N ? Number(f) * 24 / Number(w) : f,
      className: ac("lucide", j),
      ...ee
    },
    [
      ...V.map(([ce, O]) => W.createElement(ce, O)),
      ...Array.isArray(C) ? C : [C]
    ]
  )
);
/**
 * @license lucide-react v0.468.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */
const nn = (d, w) => {
  const f = W.forwardRef(
    ({ className: N, ...j }, C) => W.createElement(hd, {
      ref: C,
      iconNode: w,
      className: ac(`lucide-${dd(d)}`, N),
      ...j
    })
  );
  return f.displayName = `${d}`, f;
};
/**
 * @license lucide-react v0.468.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */
const md = nn("ArrowUpRight", [
  ["path", { d: "M7 7h10v10", key: "1tivn9" }],
  ["path", { d: "M7 17 17 7", key: "1vkiza" }]
]);
/**
 * @license lucide-react v0.468.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */
const tc = nn("Check", [["path", { d: "M20 6 9 17l-5-5", key: "1gmf2c" }]]);
/**
 * @license lucide-react v0.468.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */
const vd = nn("Circle", [
  ["circle", { cx: "12", cy: "12", r: "10", key: "1mglay" }]
]);
/**
 * @license lucide-react v0.468.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */
const yd = nn("Copy", [
  ["rect", { width: "14", height: "14", x: "8", y: "8", rx: "2", ry: "2", key: "17jyea" }],
  ["path", { d: "M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2", key: "zix9uf" }]
]);
/**
 * @license lucide-react v0.468.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */
const gd = nn("MousePointer2", [
  [
    "path",
    {
      d: "M4.037 4.688a.495.495 0 0 1 .651-.651l16 6.5a.5.5 0 0 1-.063.947l-6.124 1.58a2 2 0 0 0-1.438 1.435l-1.579 6.126a.5.5 0 0 1-.947.063z",
      key: "edeuup"
    }
  ]
]);
/**
 * @license lucide-react v0.468.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */
const wd = nn("Pencil", [
  [
    "path",
    {
      d: "M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z",
      key: "1a8usu"
    }
  ],
  ["path", { d: "m15 5 4 4", key: "1mk7zo" }]
]);
/**
 * @license lucide-react v0.468.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */
const xd = nn("RotateCcw", [
  ["path", { d: "M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8", key: "1357e3" }],
  ["path", { d: "M3 3v5h5", key: "1xhq8a" }]
]);
/**
 * @license lucide-react v0.468.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */
const kd = nn("Square", [
  ["rect", { width: "18", height: "18", x: "3", y: "3", rx: "2", key: "afitv7" }]
]);
/**
 * @license lucide-react v0.468.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */
const Sd = nn("Type", [
  ["polyline", { points: "4 7 4 4 20 4 20 7", key: "1nosan" }],
  ["line", { x1: "9", x2: "15", y1: "20", y2: "20", key: "swin9y" }],
  ["line", { x1: "12", x2: "12", y1: "4", y2: "20", key: "1tx1rr" }]
]);
/**
 * @license lucide-react v0.468.0 - ISC
 *
 * This source code is licensed under the ISC license.
 * See the LICENSE file in the root directory of this source tree.
 */
const Ed = nn("Undo2", [
  ["path", { d: "M9 14 4 9l5-5", key: "102s5s" }],
  ["path", { d: "M4 9h10.5a5.5 5.5 0 0 1 5.5 5.5a5.5 5.5 0 0 1-5.5 5.5H11", key: "f3b9sd" }]
]);
var nc = sc();
const _d = { cmd: "⌘", shift: "⇧", alt: "⌥", option: "⌥", ctrl: "⌃", enter: "↵", return: "↵", esc: "esc", tab: "⇥", up: "↑", down: "↓", left: "←", right: "→", backspace: "⌫" }, Cd = (d) => d.split("+").map((w) => _d[w.trim().toLowerCase()] ?? w.trim().toUpperCase());
function Nd({ rows: d, at: w }) {
  return /* @__PURE__ */ y.jsx(y.Fragment, { children: d.map(
    (f) => f && /* @__PURE__ */ y.jsx("div", { className: "ss-keys", "data-show": f.show, "data-at": w, "aria-hidden": !0, children: f.caps.map((N, j) => /* @__PURE__ */ y.jsx("kbd", { className: "ss-key", "data-down": f.down, children: N }, j)) }, f.id)
  ) });
}
const cc = { x: 0, y: 0, width: 0, height: 0 }, fc = (d) => typeof d == "string" ? d : "at" in d ? d.at : null, jd = (d, w) => (d == null ? void 0 : d.offsetWidth) && d.getBoundingClientRect().width / d.offsetWidth || w || 1;
function xu(d, w) {
  const f = d.getBoundingClientRect();
  return { left: f.left, top: f.top, scale: d.offsetWidth && f.width / d.offsetWidth || w || 1, borderX: d.clientLeft, borderY: d.clientTop };
}
function gl(d, w, f, N = xu(d, f)) {
  const j = w.getBoundingClientRect(), { scale: C } = N;
  return { x: (j.left - N.left) / C - N.borderX, y: (j.top - N.top) / C - N.borderY, width: j.width / C, height: j.height / C };
}
function zd(d, w, f, N = xu(d, f)) {
  const j = gl(d, w, f, N), C = getComputedStyle(w), V = C.transform, ee = V && V !== "none" ? V.match(/^matrix\(([^)]+)\)$/) : null;
  if (!ee) return j;
  const [I, ce, O, ie, re, oe] = ee[1].split(",").map(Number);
  if (ce || O || re || oe || !I || !ie) return j;
  const Z = j.width / I, te = j.height / ie, [q, we] = C.transformOrigin.split(" ").map(parseFloat);
  return { x: j.x - q * (1 - I), y: j.y - we * (1 - ie), width: Z, height: te };
}
const Ld = (d) => {
  const w = getComputedStyle(d);
  return w.transform !== "none" || w.translate && w.translate !== "none" || w.scale && w.scale !== "none" || w.rotate && w.rotate !== "none";
};
function Pd(d, w) {
  let f = !0;
  for (let V = w; V && V !== d; V = V.parentElement) if (Ld(V)) {
    f = !1;
    break;
  }
  if (f) return gl(d, w, 1);
  let N = 0, j = 0, C = w;
  for (; C && C !== d; ) {
    N += C.offsetLeft, j += C.offsetTop;
    const V = C.offsetParent;
    if (!V || !d.contains(V)) break;
    C = V, C !== d && (N += C.clientLeft - C.scrollLeft, j += C.clientTop - C.scrollTop);
  }
  return { x: N, y: j, width: w.offsetWidth, height: w.offsetHeight };
}
function rc(d, w) {
  const f = Object.keys(d);
  return f.length !== Object.keys(w).length ? !1 : f.every((N) => {
    const j = d[N], C = w[N];
    return C && Math.abs(j.x - C.x) < 0.5 && Math.abs(j.y - C.y) < 0.5 && Math.abs(j.width - C.width) < 0.5 && Math.abs(j.height - C.height) < 0.5;
  });
}
function dc(d) {
  const w = d.parentElement;
  if (!(w != null && w.classList.contains("ss-scroller"))) return;
  const f = d.clientHeight, N = d.scrollHeight, j = N > f ? Math.max(24, f / N * f) : 0, C = N > f ? d.scrollTop / (N - f) * (f - j) : 0;
  w.style.setProperty("--ss-thumb-h", `${j}px`), w.style.setProperty("--ss-thumb-y", `${C}px`);
}
const Rd = {
  /** Moves inside a shot (push-in, pan, a long cursor trip): peak at about 40%, long soft tail. 1.4 to 2.7 s. */
  house: [0.65, 0, 0.1, 1],
  /** The outgoing half of a move that ends in a cut: accelerates into it. */
  through: [0.8, 0, 0.1, 1],
  /** The incoming half after a cut: arrives at speed, settles. 0.6 to 0.8 s (1.6 s for a big pull-out). */
  settle: [0.05, 0.85, 0.3, 1],
  /** A cursor arriving from off-frame, already moving. */
  enter: [0.1, 0.8, 0.3, 0.95],
  /** One long cursor trip across the frame. */
  trip: [0.78, 0, 0.17, 1],
  /** The kit's camera push-in (Camera). */
  camera: [0.45, 0, 0.1, 1]
};
function Td(d) {
  const [w, f, N, j] = Rd[d], C = 3 * w, V = 3 * (N - w) - C, ee = 1 - C - V, I = 3 * f, ce = 3 * (j - f) - I, O = 1 - I - ce, ie = (oe) => ((ee * oe + V) * oe + C) * oe, re = (oe) => (3 * ee * oe + 2 * V) * oe + C;
  return (oe) => {
    if (oe <= 0) return 0;
    if (oe >= 1) return 1;
    let Z = oe;
    for (let te = 0; te < 8; te++) {
      const q = re(Z);
      if (Math.abs(q) < 1e-6) break;
      const we = Z - (ie(Z) - oe) / q;
      if (we < 0 || we > 1) break;
      Z = we;
    }
    if (Math.abs(ie(Z) - oe) > 1e-6) {
      let te = 0, q = 1;
      for (let we = 0; we < 40; we++)
        Z = (te + q) / 2, ie(Z) < oe ? te = Z : q = Z;
    }
    return ((O * Z + ce) * Z + I) * Z;
  };
}
function pc() {
  try {
    return !1;
  } catch {
    return !0;
  }
}
function Rr(d) {
  pc() && console.warn(`[stageshow] ${d}`);
}
const Lr = (d, w, f) => Math.min(f, Math.max(w, d)), zi = (d) => d < 0.5 ? 4 * d * d * d : 1 - Math.pow(-2 * d + 2, 3) / 2, Md = (d) => {
  const w = Math.sin(d * 12.9898) * 43758.5453;
  return w - Math.floor(w);
}, lc = (d) => {
  d && window.setTimeout(() => d.removeAttribute("data-touching"), 240);
};
class Pr extends Error {
}
function Od(d, w) {
  const { rootRef: f, cursorRef: N, pos: j, hovered: C, kindRef: V, keysRef: ee, dragging: I, autoUsed: ce, autoRef: O, scaleRef: ie, speed: re, layout: oe, cursor: Z, resolve: te, place: q, remeasure: we, ripple: Ne, setState: Me, setKind: ve, setKeys: Oe, setLastKeys: Ie } = w, je = Td("enter"), D = () => {
    if (d.aborted) throw new Pr();
  }, Et = (u, c) => new Promise((m, x) => {
    D();
    const k = () => {
      c(T), d.removeEventListener("abort", k), x(new Pr());
    }, T = u(() => {
      d.removeEventListener("abort", k), d.aborted ? x(new Pr()) : m();
    });
    d.addEventListener("abort", k, { once: !0 });
  }), De = () => Et((u) => requestAnimationFrame(u), cancelAnimationFrame), xe = (u) => Et((c) => setTimeout(c, u / re), clearTimeout), be = (u) => {
    let c = !0;
    const m = () => {
      c && (c = !1, d.removeEventListener("abort", m), u());
    };
    return d.addEventListener("abort", m, { once: !0 }), m;
  }, Be = async (u, c) => {
    const m = performance.now(), x = u / re;
    for (; ; ) {
      D();
      const k = Math.min(1, (performance.now() - m) / x);
      if (c(k), k === 1) return;
      await De();
    }
  }, Ye = (u) => {
    const c = [];
    for (let m = u; m && m !== f.current; m = m.parentElement) m.hasAttribute("data-target") && c.push(m);
    return c;
  }, Xe = (u) => {
    const c = f.current;
    if (!c) return;
    const m = c.querySelectorAll("[data-cursor]");
    if (!m.length && !ce.current) return;
    m.length && (ce.current = !0);
    const x = c.getBoundingClientRect(), k = x.width / c.offsetWidth || 1, T = c.dataset.cursorBase ?? "pointer";
    let H = T;
    c.setAttribute("data-hit", "");
    const Y = document.elementsFromPoint(x.left + u.x * k, x.top + u.y * k);
    c.removeAttribute("data-hit");
    const Q = Y.find((K) => {
      if (!c.contains(K) || K.closest(".ss-cursor, .ss-keys, .ss-ripple") || getComputedStyle(K).pointerEvents === "none" && !K.closest('[data-cursor], [data-target], button, a[href], [role="button"], [role="menuitem"], [role="option"], [role="tab"]')) return !1;
      let ne = 1;
      for (let ae = K; ae && ae !== c.parentElement; ae = ae.parentElement) {
        const ke = getComputedStyle(ae);
        if (ke.visibility === "hidden") return !1;
        ne *= Number(ke.opacity);
      }
      return ne > 0.15;
    });
    if (Q) {
      const K = Q.closest('[data-cursor], button, a[href], [role="button"], [role="menuitem"], [role="option"], [role="tab"]');
      H = K && c.contains(K) && K.dataset.cursor ? K.dataset.cursor : T, H !== V.current && ve(H);
      return;
    }
    m.forEach((K) => {
      const ne = K.getBoundingClientRect(), ae = (ne.left - x.left) / k, ke = (ne.top - x.top) / k;
      u.x >= ae && u.x <= ae + ne.width / k && u.y >= ke && u.y <= ke + ne.height / k && (H = K.dataset.cursor);
    }), H !== V.current && ve(H);
  };
  O.current = Xe, I.current || Xe(j.current);
  const ze = (u) => {
    if (C.current === u) return;
    const c = Ye(u);
    Ye(C.current).forEach((m) => c.includes(m) || m.removeAttribute("data-hover")), c.forEach((m) => m.setAttribute("data-hover", "")), C.current = u;
  };
  let le = ee.current.id, L = 0;
  const $ = (u) => {
    var m;
    const c = fc(u);
    return c === null ? null : ((m = f.current) == null ? void 0 : m.querySelector(`[data-target="${c}"]`)) ?? null;
  }, P = {
    get signal() {
      return d;
    },
    put(u) {
      d.aborted || Me((c) => ({ ...c, ...typeof u == "function" ? u(c) : u }));
    },
    async set(u) {
      var c;
      D(), P.put(u), await De(), await De(), (c = O.current) == null || c.call(O, j.current), D();
    },
    wait: async (u) => {
      D(), await xe(u);
    },
    rect: (u, c) => {
      const m = f.current, x = m == null ? void 0 : m.querySelector(`[data-target="${u}"]`);
      return !m || !x ? (Rr(`no element with data-target="${u}"`), cc) : c != null && c.layout ? Pd(m, x) : gl(m, x, ie.current);
    },
    center: (u) => te(u),
    caret(u, c) {
      L++;
      const m = $(u), x = f.current;
      if (!m || !x) return 0;
      const k = x.getBoundingClientRect(), T = k.width / x.offsetWidth || 1, H = k.left + c.x * T, Y = k.top + c.y * T, Q = [], K = document.createTreeWalker(m, NodeFilter.SHOW_TEXT), ne = document.createRange();
      let ae = 0;
      const ke = (Ee) => {
        for (let et = Ee.parentElement; et; et = et === m ? null : et.parentElement) {
          const _e = getComputedStyle(et);
          if (_e.opacity === "0" || _e.visibility === "hidden" || _e.display === "none") return !0;
        }
        return !1;
      };
      for (let Ee = K.nextNode(); Ee; Ee = K.nextNode()) {
        const et = Ee.textContent ?? "";
        if (!ke(Ee)) {
          for (let _e = 0; _e < et.length; _e++) {
            ne.setStart(Ee, _e), ne.setEnd(Ee, _e + 1);
            const fe = ne.getBoundingClientRect();
            (fe.width || fe.height) && Q.push({ left: fe.left, right: fe.right, mid: (fe.left + fe.right) / 2, top: fe.top, bottom: fe.bottom, at: ae + _e });
          }
          ae += et.length;
        }
      }
      if (!Q.length || Y < Q[0].top) return 0;
      if (Y > Q[Q.length - 1].bottom) return ae;
      let Ve = Q[0];
      for (const Ee of Q) Math.abs((Ee.top + Ee.bottom) / 2 - Y) < Math.abs((Ve.top + Ve.bottom) / 2 - Y) && (Ve = Ee);
      const me = Q.filter((Ee) => Math.abs(Ee.top - Ve.top) < (Ve.bottom - Ve.top) / 2), rn = me.find((Ee) => Ee.mid > H);
      return rn ? rn.at : me[me.length - 1].at + 1;
    },
    async move(u, c) {
      D();
      const m = { ...j.current }, x = te(u), k = Math.hypot(x.x - m.x, x.y - m.y);
      if (k < 0.5) return ze($(u));
      const T = Ye($(u));
      ze(Ye(C.current).find((ae) => T.includes(ae)) ?? null);
      const H = (c == null ? void 0 : c.duration) ?? Lr(260 + k * 0.9, 300, 650), Y = zi, Q = Math.min(k * 0.08, 24), K = -(x.y - m.y) / k, ne = (x.x - m.x) / k;
      await Be(H, (ae) => {
        const ke = Y(ae), Ve = Math.sin(Math.PI * ke) * Q, me = c != null && c.path ? c.path(ke, m, x) : { x: m.x + (x.x - m.x) * ke + K * Ve, y: m.y + (x.y - m.y) * ke + ne * Ve };
        q(me), Xe(me), c != null && c.onMove && nc.flushSync(() => c.onMove(me, m, ae));
      }), D(), ze($(u));
    },
    async click(u, c) {
      D(), u !== void 0 && (await P.move(u), await xe(120)), D();
      const m = u !== void 0 ? $(u) : C.current, x = N.current, k = (Z == null ? void 0 : Z.style) === "touch", T = be(() => {
        x == null || x.removeAttribute("data-pressed"), m == null || m.removeAttribute("data-pressed"), k && lc(x);
      });
      try {
        k && (x == null || x.setAttribute("data-touching", ""), await xe(140), D());
        for (let H = 0; H < (c != null && c.double ? 2 : 1); H++)
          H && await xe(70), D(), x == null || x.setAttribute("data-pressed", "true"), Z != null && Z.ripple && Ne(j.current), m == null || m.setAttribute("data-pressed", c != null && c.right ? "right" : ""), await xe(c != null && c.double ? 80 : 100), D(), x == null || x.removeAttribute("data-pressed"), m == null || m.removeAttribute("data-pressed");
      } finally {
        T();
      }
    },
    async scroll(u, c, m) {
      var Q, K;
      D();
      const x = $(u);
      if (!x) return;
      const k = x.scrollTop;
      let T = typeof c == "number" ? c : k;
      if (typeof c == "string") {
        const ne = $(c);
        ne && (T = k + (ne.getBoundingClientRect().top - x.getBoundingClientRect().top) / jd(f.current, ie.current) - ((m == null ? void 0 : m.offset) ?? 0));
      }
      if (T = Lr(T, 0, x.scrollHeight - x.clientHeight), Z) {
        const ne = gl(f.current, x, ie.current || 1), ae = j.current;
        ae.x >= ne.x + 8 && ae.x <= ne.x + ne.width - 8 && ae.y >= ne.y + 8 && ae.y <= ne.y + ne.height - 8 || (await this.move({ x: ne.x + ne.width * 0.6, y: ne.y + ne.height * 0.55 }), await this.wait(120));
      }
      const H = (Q = x.parentElement) != null && Q.classList.contains("ss-scroller") ? x.parentElement : null;
      H == null || H.setAttribute("data-scrolling", "");
      const Y = be(() => H == null ? void 0 : H.removeAttribute("data-scrolling"));
      try {
        await Be((m == null ? void 0 : m.duration) ?? Lr(420 + Math.abs(T - k) * 1.2, 500, 1400), (ne) => {
          x.scrollTop = k + (T - k) * zi(ne), x.toggleAttribute("data-scrolled", x.scrollTop > 0.5), dc(x);
        }), D();
      } finally {
        Y();
      }
      we(), (K = O.current) == null || K.call(O, j.current);
    },
    async snap(u, c) {
      var k;
      D();
      const m = c ? (k = f.current) == null ? void 0 : k.querySelector(`[data-target="${c}"]`) : f.current;
      m == null || m.setAttribute("data-instant", "");
      const x = be(() => m == null ? void 0 : m.removeAttribute("data-instant"));
      try {
        P.put(u), await De(), await De(), D();
      } finally {
        x();
      }
    },
    async key(u) {
      D();
      const c = Cd(u), m = ++le, x = ee.current;
      Ie(x.caps.length ? { ...x, show: !1, down: !1 } : null), Oe({ id: m, caps: c, show: !1, down: !1 }), await De(), await De(), D(), Oe({ id: m, caps: c, show: !0, down: !1 }), await xe(180), D(), Oe({ id: m, caps: c, show: !0, down: !0 }), await xe(140), D(), Oe({ id: m, caps: c, show: !0, down: !1 }), xe(600).then(() => {
        le === m && !d.aborted && Oe({ id: m, caps: c, show: !1, down: !1 });
      }, (k) => {
        k instanceof Pr || console.error("[stageshow] script error", k);
      });
    },
    async stagger(u, c, m = 60) {
      await Promise.all(
        u.map(async (x, k) => {
          k && await xe(m * k), D(), await c(x, k);
        })
      );
    },
    mark(u) {
      var c;
      d.aborted || (c = f.current) == null || c.setAttribute("data-mark", u);
    },
    async cursor(u) {
      D(), ve(u), await De();
    },
    async type(u, c, m) {
      const x = (m == null ? void 0 : m.interval) ?? 35;
      for (let k = 0; k <= c.length; k++)
        D(), Me((T) => ({ ...T, [u]: c.slice(0, k) })), await xe(x * (0.7 + 0.6 * Md(k)));
    },
    place(u) {
      var m;
      if (d.aborted) return;
      const c = te(u);
      q(c), (m = O.current) == null || m.call(O, c);
    },
    async enter(u, c) {
      D();
      const m = te(u), x = f.current, k = { x: 0, y: 0, w: x.offsetWidth, h: x.offsetHeight }, T = 40, H = [m.x - k.x, k.x + k.w - m.x, m.y - k.y, k.y + k.h - m.y], Y = H.indexOf(Math.min(...H)), Q = Y === 0 ? { x: k.x - T, y: m.y + k.h * 0.12 } : Y === 1 ? { x: k.x + k.w + T * 0.4, y: m.y + k.h * 0.12 } : Y === 2 ? { x: m.x - k.w * 0.06, y: k.y - T } : { x: m.x + k.w * 0.06, y: k.y + k.h + T * 0.4 };
      q(Q), ze(null), await Be((c == null ? void 0 : c.duration) ?? 700, (K) => {
        const ne = je(K), ae = { x: Q.x + (m.x - Q.x) * ne, y: Q.y + (m.y - Q.y) * ne };
        q(ae), Xe(ae);
      }), D(), ze($(u));
    },
    async drag(u, c, m) {
      var Ee, et, _e;
      D();
      const x = { ...j.current }, k = te(u), T = Math.hypot(k.x - x.x, k.y - x.y);
      ze(null);
      const H = V.current, Y = H === "ibeam" || H === "crosshair", Q = !Y && (m == null ? void 0 : m.cursor) !== "preserve", K = (Z == null ? void 0 : Z.style) === "touch", ne = (fe) => {
        const _t = 1.1428571428571428;
        return fe < 0.25 ? fe * fe / (2 * 0.25) * _t : (fe - 0.25 / 2) * _t;
      };
      K && ((Ee = N.current) == null || Ee.setAttribute("data-touching", ""), await xe(140), D());
      const ae = K ? ((et = N.current) == null ? void 0 : et.querySelector(".ss-cursor__streak")) ?? null : null, ke = [], Ve = (fe) => {
        ke.unshift({ ...fe }), ke.length > 9 && ke.pop();
        const dt = ke[ke.length - 1], _t = fe.x - dt.x, Ft = fe.y - dt.y, At = Math.min(Math.hypot(_t, Ft), 100);
        ae && (ae.style.width = `${At}px`, ae.style.left = `${-At}px`, ae.style.transform = `rotate(${Math.atan2(Ft, _t)}rad)`);
      };
      I.current = !0;
      const me = N.current, rn = be(() => {
        I.current = !1, me == null || me.removeAttribute("data-pressed"), me == null || me.removeAttribute("data-swiping"), K && lc(me);
      });
      try {
        me == null || me.setAttribute("data-pressed", "true"), await xe(K ? 170 : 60), K && (ae && (ae.style.width = "0px"), me == null || me.setAttribute("data-swiping", "")), D(), Q && !K && ve("grab"), K || await xe(70), D(), me == null || me.removeAttribute("data-pressed");
        const fe = Y ? 0 : Math.min(T * 0.06, 18), dt = T ? -(k.y - x.y) / T : 0, _t = T ? (k.x - x.x) / T : 0, Ft = Y && Math.abs(k.y - x.y) > 6;
        Ft && k.y > x.y && k.x < x.x - 2 && Rr("a text selection that ends left of where it starts overshoots and shrinks back; select text that starts a line, or fits on one");
        const At = L;
        await Be(K ? (m == null ? void 0 : m.duration) ?? Lr(180 + T * 0.5, 240, 300) : (m == null ? void 0 : m.duration) ?? Lr(360 + T * 1.1, 450, 900), (ln) => {
          var Xt;
          const pt = K ? ne(ln) : zi(ln), on = Math.sin(Math.PI * pt) * fe, Yt = Ft ? 1 - (1 - pt) * (1 - pt) : pt, wn = Ft ? pt * pt : pt, tt = ((Xt = m == null ? void 0 : m.path) == null ? void 0 : Xt.call(m, pt, x, k)) ?? { x: x.x + (k.x - x.x) * wn + dt * on, y: x.y + (k.y - x.y) * Yt + _t * on };
          nc.flushSync(() => c == null ? void 0 : c(tt, x, ln)), q(tt), K && Ve(tt);
        }), Y && c && L === At && Rr("selection drift: a text selection drag never read a.caret(), so the highlight is not under the I-beam; set it from a.caret(name, at) in onMove"), D(), Q && !K && ve(H === "grab" ? "pointer" : H);
      } finally {
        rn();
      }
      (_e = O.current) == null || _e.call(O, k);
    },
    layout: oe
  };
  for (const u of Object.keys(P)) {
    const c = P[u];
    typeof c == "function" && (P[u] = (...m) => {
      const x = c.apply(P, m);
      return x instanceof Promise && x.catch((k) => {
        k instanceof Pr || console.error("[stageshow] script error", k);
      }), x;
    });
  }
  return P;
}
function Id(d, w, f, N) {
  const j = Object.keys(w).filter(
    (C) => JSON.stringify(d[C]) !== JSON.stringify(w[C])
  );
  j.length && Rr(`loop seam: state still differs from initial at the end of the script (${j.join(", ")})`), N && Math.hypot(f.x - N.x, f.y - N.y) > 1 && Rr("loop seam: cursor does not end where it starts");
}
function Fd() {
  return /* @__PURE__ */ y.jsx("svg", { height: "24", width: "24", viewBox: "0 0 32 32", fill: "none", children: /* @__PURE__ */ y.jsxs("g", { transform: "translate(10 7)", children: [
    /* @__PURE__ */ y.jsx("path", { d: "m6.148 18.473 1.863-1.003 1.615-.839-2.568-4.816h4.332l-11.379-11.408v16.015l3.316-3.221z", fill: "#fff" }),
    /* @__PURE__ */ y.jsx("path", { d: "m6.431 17 1.765-.941-2.775-5.202h3.604l-8.025-8.043v11.188l2.53-2.442z", fill: "#000" })
  ] }) });
}
function Ad() {
  return /* @__PURE__ */ y.jsxs("svg", { width: "10", height: "16", viewBox: "0 0 10 16", fill: "none", overflow: "visible", children: [
    /* @__PURE__ */ y.jsx("path", { d: "M3 1H7M3 15H7M5 1V15", style: { stroke: "var(--ss-cursor-edge, #fff)" }, strokeWidth: "2.6", strokeLinecap: "round" }),
    /* @__PURE__ */ y.jsx("path", { d: "M3 1H7M3 15H7M5 1V15", style: { stroke: "var(--ss-cursor-line, #000)" }, strokeWidth: "1", strokeLinecap: "round" })
  ] });
}
function Dd() {
  return /* @__PURE__ */ y.jsxs("svg", { width: "17", height: "17", viewBox: "0 0 17 17", fill: "none", overflow: "visible", children: [
    /* @__PURE__ */ y.jsx("path", { d: "M8.5 0V17M0 8.5H17", style: { stroke: "var(--ss-cursor-edge, #fff)" }, strokeWidth: "2.6" }),
    /* @__PURE__ */ y.jsx("path", { d: "M8.5 0V17M0 8.5H17", style: { stroke: "var(--ss-cursor-line, #000)" }, strokeWidth: "1" })
  ] });
}
function Ud() {
  return /* @__PURE__ */ y.jsxs("svg", { width: "26", height: "26", viewBox: "0 0 32 32", fill: "none", children: [
    /* @__PURE__ */ y.jsx(
      "path",
      {
        d: "M10.6 6a1.7 1.7 0 0 1 3.4 0v6.6a1.3 1.3 0 0 1 2.6 0v.7a1.3 1.3 0 0 1 2.6 0v.7a1.3 1.3 0 0 1 2.6 0V19c0 3.1-2 5.6-5 5.6h-2.6c-2 0-3.3-.9-4.4-2.4l-3.1-4.1c-.6-.9-.4-2 .5-2.5.8-.4 1.7-.2 2.3.5l1.1 1.4V6Z",
        fill: "#fff",
        stroke: "#000",
        strokeWidth: "1.1",
        strokeLinejoin: "round"
      }
    ),
    /* @__PURE__ */ y.jsx("path", { d: "M14 12.6v3.6M16.6 13.3v3M19.2 14v2.6", stroke: "#000", strokeWidth: "1", strokeLinecap: "round" })
  ] });
}
function $d() {
  return /* @__PURE__ */ y.jsx("svg", { width: "26", height: "26", viewBox: "0 0 32 32", fill: "none", children: /* @__PURE__ */ y.jsxs("g", { transform: "translate(7 6)", children: [
    /* @__PURE__ */ y.jsx("path", { d: "m4.5557 8.5742c-.098-.375-.196-.847-.406-1.552-.167-.557-.342-.859-.47-1.233-.155-.455-.303-.721-.496-1.181-.139-.329-.364-1.048-.457-1.44-.119-.509.033-.924.244-1.206.253-.339.962-.49 1.357-.351.371.13.744.512.916.788.288.46.357.632.717 1.542.393.992.564 1.918.611 2.231l.085.452c-.001-.04-.043-1.122-.044-1.162-.035-1.029-.06-1.823-.038-2.939.002-.126.064-.587.084-.715.078-.5.305-.8.673-.979.412-.201.926-.215 1.401-.017.423.173.626.55.687 1.022.014.109.094.987.093 1.107-.013 1.025.006 1.641.015 2.174.004.231.003 1.625.017 1.469.061-.656.094-3.189.344-3.942.144-.433.405-.746.794-.929.431-.203 1.113-.07 1.404.243.285.305.446.692.482 1.153.032.405-.019.897-.02 1.245 0 .867-.021 1.324-.037 2.121-.001.038-.015.298.023.182.094-.28.188-.542.266-.745.049-.125.241-.614.359-.859.114-.234.211-.369.415-.688.2-.313.415-.448.668-.561.54-.235 1.109.112 1.301.591.086.215.009.713-.028 1.105-.061.647-.254 1.306-.352 1.648-.128.447-.274 1.235-.34 1.601-.072.394-.234 1.382-.359 1.82-.086.301-.371.978-.652 1.384 0 0-1.074 1.25-1.192 1.812-.117.563-.078.567-.101.965-.024.399.121.923.121.923s-.802.104-1.234.034c-.391-.062-.875-.841-1-1.078-.172-.328-.539-.265-.682-.023-.225.383-.709 1.07-1.051 1.113-.668.084-2.054.03-3.139.02 0 0 .185-1.011-.227-1.358-.305-.26-.83-.784-1.144-1.06l-.832-.921c-.284-.36-.629-1.093-1.243-1.985-.348-.504-1.027-1.085-1.284-1.579-.223-.425-.331-.954-.19-1.325.225-.594.675-.897 1.362-.832.519.05.848.206 1.238.537.225.19.573.534.75.748.163.195.203.276.377.509.23.307.302.459.214.121", fill: "#fff" }),
    /* @__PURE__ */ y.jsxs("g", { stroke: "#000", strokeLinecap: "round", strokeWidth: ".75", children: [
      /* @__PURE__ */ y.jsx("path", { d: "m4.5557 8.5742c-.098-.375-.196-.847-.406-1.552-.167-.557-.342-.859-.47-1.233-.155-.455-.303-.721-.496-1.181-.139-.329-.364-1.048-.457-1.44-.119-.509.033-.924.244-1.206.253-.339.962-.49 1.357-.351.371.13.744.512.916.788.288.46.357.632.717 1.542.393.992.564 1.918.611 2.231l.085.452c-.001-.04-.043-1.122-.044-1.162-.035-1.029-.06-1.823-.038-2.939.002-.126.064-.587.084-.715.078-.5.305-.8.673-.979.412-.201.926-.215 1.401-.017.423.173.626.55.687 1.022.014.109.094.987.093 1.107-.013 1.025.006 1.641.015 2.174.004.231.003 1.625.017 1.469.061-.656.094-3.189.344-3.942.144-.433.405-.746.794-.929.431-.203 1.113-.07 1.404.243.285.305.446.692.482 1.153.032.405-.019.897-.02 1.245 0 .867-.021 1.324-.037 2.121-.001.038-.015.298.023.182.094-.28.188-.542.266-.745.049-.125.241-.614.359-.859.114-.234.211-.369.415-.688.2-.313.415-.448.668-.561.54-.235 1.109.112 1.301.591.086.215.009.713-.028 1.105-.061.647-.254 1.306-.352 1.648-.128.447-.274 1.235-.34 1.601-.072.394-.234 1.382-.359 1.82-.086.301-.371.978-.652 1.384 0 0-1.074 1.25-1.192 1.812-.117.563-.078.567-.101.965-.024.399.121.923.121.923s-.802.104-1.234.034c-.391-.062-.875-.841-1-1.078-.172-.328-.539-.265-.682-.023-.225.383-.709 1.07-1.051 1.113-.668.084-2.054.03-3.139.02 0 0 .185-1.011-.227-1.358-.305-.26-.83-.784-1.144-1.06l-.832-.921c-.284-.36-.629-1.093-1.243-1.985-.348-.504-1.027-1.085-1.284-1.579-.223-.425-.331-.954-.19-1.325.225-.594.675-.897 1.362-.832.519.05.848.206 1.238.537.225.19.573.534.75.748.163.195.203.276.377.509.23.307.302.459.214.121", strokeLinejoin: "round" }),
      /* @__PURE__ */ y.jsx("path", { d: "m11.566 12.734v-3.459" }),
      /* @__PURE__ */ y.jsx("path", { d: "m9.551 12.746-.016-3.473" }),
      /* @__PURE__ */ y.jsx("path", { d: "m7.555 9.305.021 3.426" })
    ] })
  ] }) });
}
function Wd() {
  return /* @__PURE__ */ y.jsx("svg", { width: "30", height: "30", viewBox: "0 0 32 32", fill: "none", children: /* @__PURE__ */ y.jsxs("g", { transform: "translate(8 9)", children: [
    /* @__PURE__ */ y.jsx("path", { d: "m3.44281398 1.68449726c-.74326136.27630142-1.05584685.8131257-1.07636853 1.38003696-.01344897.37336893.06665513.72649286.23114214 1.18694303-.02596219-.07267623.09676488.29282004.12116236.37362273.05052942.16918921-.4865367-.05865774-.81377307.00741883-.36363321.07113868-.84783757.38332307-1.10006887.79754775-.29643467.48542737-.3109609 1.04368567-.08235979 2.04824266.12491868.54736183.36572145 1.00836814.71076689 1.44594879.15329951.1944118.5713628.64726015.60307236.6875974l.84854343.94062339c.15080214.1358526.25794954.2361946.57590427.5380259.3147558.2987762.4647038.4380078.60308951.555976.05846214.0492474.10784267.1797116.12740685.3736249.01609788.1595565.01049553.3375341-.0090192.5090254-.00674888.0593077-.01325791.1020883-.01698742.1224696-.04189161.228932.13269563.4403386.36541902.4424835.21585671.0019894.38528595.0046546.82216479.0123538.09483476.0016698.09483476.0016698.18993053.0033129 1.16876447.0200186 1.75308289.0147904 2.17807912-.0385723.45429894-.0572869.92650915-.6110188 1.32698393-1.2957591.34289141.6108338.81859723 1.2057867 1.2995685 1.2820532.1510118.0244148.3353555.0322555.548787.0275887.1606725-.0035131.3307029-.0140241.5021961-.0293376.1276907-.0114022.2293359-.0228648.29003-.0307451.2258836-.0293282.373669-.251611.3133108-.4712481-.0130351-.0474332-.0339838-.1345011-.0551094-.2441635-.0245945-.1276687-.0423383-.2523857-.0503381-.365988-.0050217-.0713101-.0059948-.1359317-.0027687-.1918983.0059157-.0980798.0077938-.1530073.0108033-.281125.0010795-.0448938.0010795-.0448938.0024606-.0845172.0054208-.1364475.0233824-.2649146.0815132-.544638.0250088-.1201275.1473169-.352189.3398902-.639435.0571394-.0852302.1195783-.1742239.1864664-.26609712.1272143-.17473362.2641361-.35131772.4011075-.52030772.082051-.10123129.145482-.17695689.1808122-.21807676.2967593-.42378347.612817-1.11823437.7291396-1.52536348.1117407-.39153936.202351-1.12501196.254373-1.81690429.029923-.39968605.0410555-.72381216.0410555-1.23011613.0000742-.09758414.0000742-.09758414.0002975-.17670236.0003569-.11115478.0003569-.11115478.000115-.20711835-.0008934-.15683883-.0055282-.31323355-.0207085-.69507578-.0313109-.81293139-.4771727-1.33911388-1.1344906-1.44058831-.559108-.08631314-1.0586051.08188477-1.2779293.31625977-.0755526.08073733.0036753-.2781823-.2159489-.62316278-.1644465-.25841586-.593184-.58905957-.9209287-.65355552-.335487-.06535532-.73539548-.05811715-1.1017193.00667481-.32093157.05742909-.68608434.33741751-.87176225.64688068-.12411885.20686477.03884667-.00592296-.09368743-.23401341-.18231052-.31422641-.60754287-.59486422-1.01411454-.67799709-.34643562-.07139428-.74182572-.04452925-1.09945614.0633873-.43336319.1291117-1.01795827.61460976-.94899189 1.15552627-.34375-.54091651-1.25026717-.691379-1.97906097-.42111797z", fill: "#000" }),
    /* @__PURE__ */ y.jsx("path", { d: "m7.31951013 1.62138197c.20710357.04234751.44724204.20083012.51632974.31990811.08404358.1446387.15562749.36413806.21048667.6366124.02933373.14569467.12179446 1.2125285.29383112 1.32370243.41279229.04533731.41279229.04533731.52658055-.12364345.03545705-.07383858.03545705-.07383858.04226523-.1029106.01416796-.06009544.02463332-.12677987.0351322-.21754028l.00854738-.07915386.00047673-.00942804.00327525-.03167185c.01085148-.11424313.04184125-.4312127.05388392-.53034902.03788792-.31189663.08766449-.52757784.13944093-.6138719.0713024-.11883734.31942298-.28274442.43149612-.30279961.2804398-.04960082.58940103-.05519288.82623993-.00905543.1084394.02134018.3709471.22378689.432331.32024744.1291079.20279957.2524316.84889766.3225486 1.4970065-.0102194.04624251-.0102194.04624251.1640069.28984194.5843296-.06677889.5843296-.06677889.5703629-.17490247.0159511-.03856429.0284824-.08294031.045969-.15118961.0423876-.16089067.0697594-.25204451.111066-.35549917.0288558-.07227096.0592914-.13391873.0904889-.18278042.1209187-.19031132.4335712-.319392.7077174-.27707028.2943447.04543991.4816904.26653537.4994912.72869815.0148821.37434892.0193146.5239164.0201469.6700184l-.0004247.37954865c0 .48831141-.0104951.79388164-.0389535 1.17400348-.0480918.63962116-.1348512 1.34192123-.227649 1.66708484-.0946325.33121345-.3766371.95084197-.6003915 1.27298482-.0161892.01580846-.0841508.09694273-.1710333.20413492-.1445842.17838247-.2892181.36491271-.4247891.5511244-.0723398.09936149-.1402862.19620479-.2030964.2898938-.2440054.36396314-.400553.66098894-.4512157.90434304-.0659304.3172546-.0893838.4850003-.0966379.6675968-.0017072.0490782-.0017072.0490782-.002845.096677-.0028064.119476-.004437.1671639-.0097087.2545848-.0052654.091322-.0038193.187354.00332.2887353.0103318.1467182.1058713.3478531.1058713.3478531s-.2321503-.0119819-.3742084-.0088758c-.1718098.0037567-.3147843-.0023244-.4138162-.0183342-.1440353-.0228411-.53014068-.5057331-.7278511-.8821737-.30227042-.5764228-1.03604858-.5484427-1.33684295-.0394061-.26854779.4591613-.65918083.9172326-.7740684.9317199-.37404082.0469647-.94643778.0520862-2.07160079.0328144-.09480875-.0016381-.46003446-.0128683-.64600494-.0157445-.18597048-.0028763.05008807-.1790283.02786486-.399297-.03726222-.36933-.15125405-.6704984-.38877094-.8705429-.12241569-.1043631-.26774964-.2393104-.56509654-.5215613-.33323493-.3163366-.44236499-.4185353-.57290215-.533275l-.80130455-.89071892c-.03955779-.05174211-.45812831-.5051399-.5872217-.6688539-.28069963-.35597842-.47062947-.71959073-.56844755-1.14820437-.18921973-.83150113-.1793328-1.21146622-.00855589-1.49112273.13743587-.2257023.43815377-.4195862.60596039-.45241793.17165981-.03465512.55153059-.01648617.62179422.02229321.09902279.05401056.13357243.07300285.16379074.09097645.03572494.02124891.05965747.03799198.08182912.05708809.03426437.02951139.07235014.07170412.12420211.14044502.03611591.04821025.07806642.1053997.1423779.19304882.06054643.0816627.09183576.12069421.13369221.1590035.28038907.25662728.68391532.03238058.65052057-.32606956-.00567036-.06086415-.02203766-.12694598-.05458621-.23708502-.04356824-.15021272.00433013-.05284275-.26002629-.56642281-.08720664-.16942124-.13955864-.28835362-.17428227-.4046158l-.03412852-.10219113c-.03838756-.11059767-.09558223-.26854489-.12612861-.35199347l-.02009957-.05467087.002.008-.05974804-.17751191c-.09232236-.28807194-.13413567-.51358087-.12645475-.72681781.01040781-.28751553.16037753-.54506871.58790983-.70400047.40142488-.1488616 1.07786076.00117106 1.20581167.27856864.04319814.09369738.08927466.21199471.13900415.35457792l.03930997.11680217c.05539717.16759437.13470873.41493582.13860471.42816881.02724222.08344874.0471839.13860719.06943813.18441246.00217869.06301886.00217869.06301886.35429398.23177937.41699479-.29154152.41699479-.29154152.38019201-.37525838.00571063-.08773482.00758408-.17356287.00965287-.37317647.00242546-.23402898.00423842-.33154773.00994479-.45966208.01316411-.29554918.0437926-.51142116.09291227-.63864415.09160418-.23801371.25279279-.40993649.4432431-.46667832.24458613-.07380253.51465245-.09215236.73323569-.04710649zm1.21356228 4.27672201c-.20710459.00095412-.37422255.16961903-.37326843.37672361l.016 3.473c.00095412.20710459.16961903.37422251.37672361.37326841.20710459-.0009541.37422255-.16961901.37326843-.37672359l-.016-3.473c-.00095412-.20710459-.16961903-.37422255-.37672361-.37326843zm2.03332759.00229602c-.2071068 0-.375.16789322-.375.375v3.459c0 .20710678.1678932.375.375.375s.375-.16789322.375-.375v-3.459c0-.20710678-.1678932-.375-.375-.375zm-4.01399856.02930704c-.20710289.00126946-.37396385.17018863-.3726944.37729152l.021 3.426c.00126946.20710289.17018863.37396384.37729152.37269444.20710289-.0012695.37396385-.17018867.3726944-.37729156l-.021-3.426c-.00126946-.20710289-.17018863-.37396385-.37729152-.3726944z", fill: "#fff" })
  ] }) });
}
function Bd() {
  return /* @__PURE__ */ y.jsxs("svg", { width: "16", height: "16", viewBox: "0 0 20 20", fill: "none", xmlns: "http://www.w3.org/2000/svg", children: [
    /* @__PURE__ */ y.jsx("circle", { cx: "10", cy: "10", r: "8", stroke: "rgba(0,0,0,0.15)", strokeWidth: "2" }),
    /* @__PURE__ */ y.jsx("path", { d: "M10 2A8 8 0 0 1 18 10", stroke: "black", strokeWidth: "2", strokeLinecap: "round" })
  ] });
}
const ic = "M0-8.4 2.55-3.65H-2.55ZM0 8.4 2.55 3.65H-2.55Z";
function Li({ turn: d }) {
  return /* @__PURE__ */ y.jsx("svg", { width: "21", height: "21", viewBox: "-14 -14 28 28", overflow: "visible", children: /* @__PURE__ */ y.jsxs("g", { transform: `rotate(${d})`, strokeLinejoin: "round", children: [
    /* @__PURE__ */ y.jsx("path", { d: ic, style: { fill: "var(--ss-cursor-edge, #fff)", stroke: "var(--ss-cursor-edge, #fff)" }, strokeWidth: "3.2" }),
    /* @__PURE__ */ y.jsx("path", { d: ic, style: { fill: "var(--ss-cursor-line, #000)", stroke: "var(--ss-cursor-line, #000)" }, strokeWidth: "1.2" })
  ] }) });
}
const Hd = () => /* @__PURE__ */ y.jsx(Li, { turn: 0 }), Vd = () => /* @__PURE__ */ y.jsx(Li, { turn: 90 }), Qd = () => /* @__PURE__ */ y.jsx(Li, { turn: -45 }), Kd = () => /* @__PURE__ */ y.jsx(Li, { turn: 45 }), oc = {
  pointer: Fd,
  ibeam: Ad,
  crosshair: Dd,
  hand: Ud,
  open: $d,
  grab: Wd,
  wait: Bd,
  "resize-ns": Hd,
  "resize-ew": Vd,
  "resize-nwse": Qd,
  "resize-nesw": Kd
}, Yd = {
  pointer: { x: 7.5, y: 5.25 },
  ibeam: { x: 5, y: 8 },
  crosshair: { x: 8.5, y: 8.5 },
  hand: { x: 9.75, y: 3.25 },
  open: { x: 11.7, y: 10.4 },
  grab: { x: 12, y: 12 },
  wait: { x: 8, y: 8 },
  "resize-ns": { x: 10.5, y: 10.5 },
  "resize-ew": { x: 10.5, y: 10.5 },
  "resize-nwse": { x: 10.5, y: 10.5 },
  "resize-nesw": { x: 10.5, y: 10.5 }
}, Xd = { x: 4, y: 3 };
function Gd() {
  return /* @__PURE__ */ y.jsx("svg", { width: "22", height: "22", viewBox: "0 0 22 22", className: "ss-cursor__arrow", "aria-hidden": !0, children: /* @__PURE__ */ y.jsx("path", { d: "M4 3 18.5 9.6 11.8 11.8 9.6 18.5Z" }) });
}
function Zd({ cursorRef: d, style: w = "real", kind: f }) {
  return /* @__PURE__ */ y.jsxs("div", { ref: d, className: "ss-cursor", "data-style": w, "data-kind": f, "aria-hidden": !0, children: [
    w === "touch" && /* @__PURE__ */ y.jsx("span", { className: "ss-cursor__streak" }),
    /* @__PURE__ */ y.jsxs("div", { className: "ss-cursor__press", children: [
      (w === "circle" || w === "touch") && /* @__PURE__ */ y.jsx("span", { className: "ss-cursor__dot" }),
      w !== "circle" && w !== "touch" && Object.keys(oc).map((N) => {
        const j = w === "arrow";
        if (j && N !== "pointer" && N !== "ibeam") return null;
        const C = j && N === "pointer" ? Gd : oc[N], V = j && N === "pointer" ? Xd : Yd[N], ee = j && f !== "ibeam" ? "pointer" : f;
        return /* @__PURE__ */ y.jsx(
          "div",
          {
            className: "ss-cursor__glyph",
            "data-glyph": N,
            "data-active": N === ee,
            style: { marginLeft: -V.x, marginTop: -V.y, transformOrigin: `${V.x}px ${V.y}px` },
            children: /* @__PURE__ */ y.jsx(C, {})
          },
          N
        );
      })
    ] })
  ] });
}
function qd(d, w) {
  const f = document.createElement("span");
  f.className = "ss-ripple", f.style.left = `${w.x}px`, f.style.top = `${w.y}px`, d.appendChild(f), f.addEventListener("animationend", () => f.remove());
}
const hc = W.createContext({
  theme: "light",
  palette: "accent",
  fidelity: "standard",
  layout: "wide"
}), Jd = () => W.useContext(hc), mc = W.createContext(!1);
function bd() {
  const d = W.useContext(mc), [w, f] = W.useState(!1);
  return W.useEffect(() => {
    const N = window.matchMedia("(prefers-reduced-motion: reduce)"), j = () => f(N.matches);
    return j(), N.addEventListener("change", j), () => N.removeEventListener("change", j);
  }, []), d || w;
}
const nr = {
  now: () => performance.now(),
  raf: (d) => requestAnimationFrame(d),
  cancelRaf: (d) => cancelAnimationFrame(d),
  // Layout must finish even when a preview is paused. Keep these callbacks
  // separate: running arbitrary motion RAFs at a frozen timestamp can still
  // advance a spring that integrates once per callback.
  layoutRaf: (d) => {
    var w;
    return ((w = nr.recording) == null ? void 0 : w.requestLayoutFrame(d)) ?? requestAnimationFrame(d);
  },
  cancelLayoutRaf: (d) => {
    const w = nr.recording;
    w ? w.cancelLayoutFrame(d) : cancelAnimationFrame(d);
  },
  timeout: (d, w) => window.setTimeout(d, w),
  clearTimeout: (d) => window.clearTimeout(d),
  /** The recorder's control while one drives the page, else null. */
  get recording() {
    var d;
    return typeof window > "u" ? null : ((d = window.__stageshow) == null ? void 0 : d.clock) ?? null;
  }
}, e0 = {};
function t0({
  width: d,
  height: w,
  initial: f = e0,
  script: N,
  poster: j,
  cursor: C,
  hover: V,
  play: ee = "loop",
  compact: I,
  keys: ce = "bottom",
  palette: O = "accent",
  greys: ie,
  fidelity: re = "standard",
  specimen: oe,
  unframed: Z,
  speed: te = 1,
  accent: q,
  tokens: we,
  ground: Ne,
  fill: Me = !1,
  theme: ve = "light",
  className: Oe,
  children: Ie
}) {
  const je = ee === "hover" && typeof window < "u" && window.matchMedia("(hover: none)").matches ? "once" : ee, [D, Et] = W.useState("wide"), De = W.useRef(D);
  De.current = D;
  const xe = () => {
    const R = C.at;
    return typeof R == "object" && "wide" in R ? R[De.current] : R;
  }, [be, Be] = W.useState(!1), Ye = D === "compact" && I ? I.width : d, Xe = D === "compact" && I ? I.height : w, ze = W.useRef(null), le = W.useRef(null), L = W.useRef(null), $ = bd(), P = !N || $, [u, c] = W.useState(() => P && j ? j : f), m = W.useRef(u);
  m.current = u;
  const [x, k] = W.useState(1), T = W.useRef(1);
  T.current = x;
  const H = typeof window > "u" ? {} : window.__stageshow ?? {}, Y = te / (H.slow ?? 1), Q = H.theme ?? ve, [K, ne] = W.useState((C == null ? void 0 : C.kind) ?? "pointer"), ae = (R) => {
    const ue = le.current;
    !ue || $ || qd(ue, R);
  }, ke = W.useRef(K);
  ke.current = K;
  const [Ve, me] = W.useState({ id: 0, caps: [], show: !1, down: !1 }), [rn, Ee] = W.useState(null), et = W.useRef(Ve);
  et.current = Ve;
  const _e = W.useRef({ x: 0, y: 0 }), fe = W.useRef(null), [dt, _t] = W.useState(0), Ft = W.useRef(!1), At = W.useRef(!1), ln = W.useRef(null);
  W.useLayoutEffect(() => {
    const R = ze.current;
    if (!R) return;
    const ue = () => {
      var Zt, xn;
      const Se = R.clientWidth, nt = !!((Zt = R.parentElement) != null && Zt.closest("[data-ss-wide]")), Ct = I && !nt && Se < I.below ? "compact" : "wide";
      Et(Ct);
      const at = Me || !!((xn = R.parentElement) != null && xn.closest("[data-ss-fill]"));
      Be(at);
      const de = Ct === "compact" ? I.width : d, Ge = Math.min(at ? 2 : 1, Se / de);
      k(Ge), _t(Math.max(0, (Se - de * Ge) / 2));
    };
    ue();
    const b = new ResizeObserver(ue);
    b.observe(R);
    const Re = new MutationObserver(ue);
    for (let Se = R.parentElement; Se; Se = Se.parentElement)
      Re.observe(Se, { attributes: !0, attributeFilter: ["data-ss-wide", "data-ss-fill"] });
    return () => {
      b.disconnect(), Re.disconnect();
    };
  }, [d, I == null ? void 0 : I.below, I == null ? void 0 : I.width, Me]);
  const [pt, on] = W.useState({}), Yt = W.useCallback(() => {
    const R = le.current;
    if (!R) return {};
    const ue = {}, b = R.querySelectorAll("[data-target]");
    if (!b.length) return ue;
    const Re = xu(R, T.current);
    return b.forEach((Se) => {
      ue[Se.dataset.target] = zd(R, Se, T.current, Re);
    }), ue;
  }, []), wn = W.useRef({ n: 0, frame: 0, owed: !1 }), tt = W.useCallback(() => {
    const R = wn.current;
    if (R.frame || (R.frame = nr.layoutRaf(() => {
      if (R.n = 0, R.frame = 0, !R.owed) return;
      R.owed = !1;
      const b = Yt();
      on((Re) => rc(Re, b) ? Re : b);
    })), R.n >= 4) {
      R.owed = !0;
      return;
    }
    R.n++;
    const ue = Yt();
    on((b) => rc(b, ue) ? b : ue);
  }, [Yt]);
  W.useLayoutEffect(tt), W.useLayoutEffect(() => () => {
    nr.cancelLayoutRaf(wn.current.frame), wn.current = { n: 0, frame: 0, owed: !1 };
  }, []), W.useEffect(() => {
    const R = le.current;
    if (R)
      return R.addEventListener("transitionend", tt), R.addEventListener("animationend", tt), () => {
        R.removeEventListener("transitionend", tt), R.removeEventListener("animationend", tt);
      };
  }, [tt]);
  const Xt = W.useCallback((R) => pt[R] ?? cc, [pt]), [Pi, Tr] = W.useState(!0);
  W.useLayoutEffect(() => {
    Tr(!0);
    let R = !0, ue = 0;
    const b = () => {
      ue = nr.layoutRaf(() => {
        ue = nr.layoutRaf(() => R && Tr(!1));
      });
    };
    return !document.fonts || document.fonts.status === "loaded" ? b() : document.fonts.ready.then(() => R && b()), () => {
      R = !1, nr.cancelLayoutRaf(ue);
    };
  }, [D]);
  const un = W.useRef(0), Wn = W.useRef(0), sn = W.useRef(!1), an = W.useRef(null), Gt = W.useCallback((R) => {
    Wn.current && !sn.current && Math.hypot(R.x - _e.current.x, R.y - _e.current.y) > 0.5 && (sn.current = !0, an.current ?? (an.current = performance.now() - Wn.current)), _e.current = R, un.current = performance.now();
    const ue = L.current;
    ue && (ue.style.transform = `translate(${R.x}px, ${R.y}px)`, ue.removeAttribute("data-idle"));
  }, []), Dt = W.useCallback((R) => {
    typeof R == "object" && R !== null && "wide" in R && (R = De.current === "compact" ? R.compact : R.wide);
    const ue = fc(R);
    if (ue === null) return R;
    const b = le.current, Re = b == null ? void 0 : b.querySelector(`[data-target="${ue}"]`);
    if (!b || !Re)
      return Rr(`no element with data-target="${ue}"`), _e.current;
    const Se = gl(b, Re, T.current), nt = typeof R == "string" ? { x: 0.5, y: 0.5 } : R;
    return { x: Se.x + Se.width * nt.x, y: Se.y + Se.height * nt.y };
  }, []);
  W.useLayoutEffect(() => {
    if (!P || !V) return;
    const R = le.current;
    V.forEach((ue) => {
      var b;
      return (b = R == null ? void 0 : R.querySelector(`[data-target="${ue}"]`)) == null ? void 0 : b.setAttribute("data-hover", "");
    });
  }), W.useLayoutEffect(() => {
    C && !Wn.current && Gt(Dt(xe()));
  }, [x, D]);
  const Bn = W.useRef(0), ht = W.useRef(0), Ut = W.useCallback(() => {
    var R;
    ++Bn.current, cancelAnimationFrame(ht.current), ht.current = 0, (R = le.current) == null || R.removeAttribute("data-settling");
  }, []), rr = W.useCallback((R = !1) => {
    var Re, Se, nt, Ct, at;
    Ut();
    const ue = Bn.current;
    if (At.current = !1, c(f), ne((C == null ? void 0 : C.kind) ?? "pointer"), me((de) => ({ ...de, show: !1, down: !1 })), Ee(null), (Re = le.current) == null || Re.querySelectorAll("[data-hover],[data-pressed]").forEach((de) => {
      de.removeAttribute("data-hover"), de.removeAttribute("data-pressed");
    }), (Se = le.current) == null || Se.removeAttribute("data-mark"), (nt = le.current) == null || nt.querySelectorAll("[data-scrolled]").forEach((de) => {
      de.scrollTop = 0, de.removeAttribute("data-scrolled"), dc(de);
    }), (Ct = le.current) == null || Ct.querySelectorAll("[data-scrolling]").forEach((de) => de.removeAttribute("data-scrolling")), (at = L.current) == null || at.removeAttribute("data-pressed"), ln.current = null, !C) return;
    if (!R) {
      ht.current = requestAnimationFrame(() => {
        var de;
        ht.current = 0, Gt(Dt(xe())), (de = fe.current) == null || de.call(fe, _e.current);
      });
      return;
    }
    const b = le.current;
    b == null || b.setAttribute("data-settling", ""), ht.current = requestAnimationFrame(() => {
      const de = { ..._e.current }, Ge = Dt(xe()), Zt = Lr(320 + Math.hypot(Ge.x - de.x, Ge.y - de.y) * 0.7, 380, 700), xn = performance.now(), kn = () => {
        if (Bn.current !== ue) return;
        const lr = Math.min(1, (performance.now() - xn) / Zt), mt = zi(lr);
        Gt({ x: de.x + (Ge.x - de.x) * mt, y: de.y + (Ge.y - de.y) * mt }), lr < 1 ? ht.current = requestAnimationFrame(kn) : (ht.current = 0, b == null || b.removeAttribute("data-settling"));
      };
      kn();
    });
  }, [D]), Mr = W.useMemo(
    () => (R) => Od(R, {
      rootRef: le,
      cursorRef: L,
      pos: _e,
      hovered: ln,
      kindRef: ke,
      keysRef: et,
      dragging: At,
      autoUsed: Ft,
      autoRef: fe,
      scaleRef: T,
      speed: Y,
      layout: D,
      cursor: C,
      resolve: Dt,
      place: Gt,
      remeasure: tt,
      ripple: ae,
      setState: c,
      setKind: ne,
      setKeys: me,
      setLastKeys: Ee
    }),
    [Dt, Gt, Y, D]
    // eslint-disable-line react-hooks/exhaustive-deps
  );
  W.useEffect(() => {
    const R = le.current;
    if (P || !N)
      return rr(), R.removeAttribute("data-offscreen"), c(j ?? f), Ut;
    rr();
    const ue = ze.current;
    let b = null, Re = !1, Se = !1, nt = !1;
    const Ct = (C == null ? void 0 : C.idle) ?? 4e3, at = 1200;
    let de = 0, Ge = 0;
    const Zt = () => {
      window.clearInterval(de), !(!C || Ct === !1) && (un.current = performance.now(), de = window.setInterval(() => {
        var cn;
        const ye = L.current;
        if (!ye) return;
        const vt = performance.now();
        if (!sn.current) {
          an.current === null && vt - un.current > at && ye.setAttribute("data-idle", "");
          return;
        }
        ye.hasAttribute("data-pressed") || (cn = le.current) != null && cn.querySelector("[data-hover]") ? un.current = vt : vt - un.current > Ct && ye.setAttribute("data-idle", "");
      }, 150));
    }, xn = () => {
      Wn.current = performance.now(), sn.current = !1, window.clearTimeout(Ge);
      const ye = L.current, vt = an.current;
      Ct === !1 || !ye || vt === null || vt <= at || (ye.setAttribute("data-idle", ""), Ge = window.setTimeout(() => ye.removeAttribute("data-idle"), vt - 400));
    }, kn = () => {
      var ye;
      window.clearInterval(de), window.clearTimeout(Ge), Wn.current = 0, (ye = L.current) == null || ye.removeAttribute("data-idle");
    }, lr = () => {
      window.clearInterval(de), window.clearTimeout(Ge);
      const ye = L.current, vt = () => (ye == null ? void 0 : ye.hasAttribute("data-pressed")) || R.querySelector("[data-hover]");
      if (!C || Ct === !1 || !ye || ye.hasAttribute("data-idle") || vt()) return;
      const cn = (sn.current ? Ct : at) - (performance.now() - un.current);
      Ge = window.setTimeout(() => {
        vt() || ye.setAttribute("data-idle", "");
      }, Math.max(0, cn));
    }, mt = () => {
      if (b || nt || !Re || document.hidden || je === "hover" && !Se) return;
      Ut(), C && Gt(Dt(xe())), b = new AbortController();
      const ye = b.signal;
      Zt();
      const vt = Mr(ye);
      (async () => {
        do {
          xn();
          try {
            await N(vt);
          } catch (cn) {
            if (cn instanceof Pr) return;
            console.error("[stageshow] script error", cn), b = null, kn();
            return;
          }
          je === "loop" && pc() && Id(m.current, f, _e.current, C ? Dt(xe()) : null);
        } while (je === "loop" && !ye.aborted);
        je === "once" && !ye.aborted && (nt = !0, lr());
      })();
    }, ir = (ye = !1) => {
      kn(), b && (b.abort(), b = null, nt || rr(ye));
    }, or = () => R.toggleAttribute("data-offscreen", !Re || document.hidden);
    or();
    const kl = new IntersectionObserver(([ye]) => {
      Re = ye.isIntersecting, or(), Re ? mt() : ir();
    });
    kl.observe(ue);
    const Or = () => {
      or(), document.hidden ? ir() : mt();
    };
    document.addEventListener("visibilitychange", Or);
    const Ir = () => {
      Se = !0, mt();
    }, Fr = () => {
      Se = !1, ir(!0);
    };
    return je === "hover" && (ue.addEventListener("pointerenter", Ir), ue.addEventListener("pointerleave", Fr)), () => {
      kl.disconnect(), document.removeEventListener("visibilitychange", Or), ue.removeEventListener("pointerenter", Ir), ue.removeEventListener("pointerleave", Fr), kn(), b == null || b.abort(), b = null, fe.current = null, Ut();
    };
  }, [P, N, Mr, je, D]), W.useLayoutEffect(() => {
    var R;
    C && !P && !At.current && ((R = fe.current) == null || R.call(fe, _e.current));
  }, [u]);
  const wl = W.useMemo(() => ({ theme: Q, palette: O, fidelity: re, layout: D }), [Q, O, re, D]), xl = C && (!N || !P || C.still);
  return /* @__PURE__ */ y.jsx("div", { ref: ze, className: `ss-fit${Oe ? ` ${Oe}` : ""}`, style: { maxWidth: be ? void 0 : d, height: Xe * x }, children: /* @__PURE__ */ y.jsxs(
    "div",
    {
      ref: le,
      className: "ss-stage",
      "data-specimen": oe || void 0,
      "data-unframed": Z || void 0,
      "data-still": P || void 0,
      "data-placing": Pi || void 0,
      "data-theme": Q,
      "data-palette": O,
      "data-greys": ie === "cool" ? "cool" : void 0,
      "data-fidelity": re,
      "data-layout": D,
      style: {
        width: Ye,
        height: Xe,
        marginLeft: dt || void 0,
        transform: `scale(${x})`,
        ...we,
        ...q ? { "--ss-accent": q, "--ss-accent-2": q, "--ss-accent-soft": `color-mix(in srgb, ${q} 14%, transparent)` } : null
      },
      children: [
        Ne && /* @__PURE__ */ y.jsx(
          "div",
          {
            className: "ss-ground",
            "aria-hidden": !0,
            style: Array.isArray(Ne) ? { "--ss-orb-1": Ne[0], "--ss-orb-2": Ne[1], ...Ne[2] ? { "--ss-orb-3": Ne[2] } : null } : void 0
          }
        ),
        /* @__PURE__ */ y.jsx(mc.Provider, { value: P, children: /* @__PURE__ */ y.jsx(hc.Provider, { value: wl, children: Ie(u, Xt, D) }) }),
        N && /* @__PURE__ */ y.jsx(Nd, { rows: [rn, Ve], at: typeof ce == "string" ? ce : ce[D] }),
        xl && /* @__PURE__ */ y.jsx(Zd, { cursorRef: L, style: C.style, kind: K })
      ]
    }
  ) });
}
function yl() {
  return /* @__PURE__ */ y.jsxs("span", { className: "ss-window__lights", children: [
    /* @__PURE__ */ y.jsx("span", { className: "ss-window__dot" }),
    /* @__PURE__ */ y.jsx("span", { className: "ss-window__dot" }),
    /* @__PURE__ */ y.jsx("span", { className: "ss-window__dot" })
  ] });
}
function n0() {
  return /* @__PURE__ */ y.jsxs("svg", { className: "ss-window__lock", width: "7", height: "8", viewBox: "0 0 7 8", "aria-hidden": !0, children: [
    /* @__PURE__ */ y.jsx("path", { d: "M1.5 3.3V2.4a2 2 0 0 1 4 0v.9", fill: "none", stroke: "currentColor", strokeWidth: "1.1" }),
    /* @__PURE__ */ y.jsx("rect", { x: "0", y: "3.3", width: "7", height: "4.7", rx: "1.2", fill: "currentColor" })
  ] });
}
function uc({ back: d }) {
  return /* @__PURE__ */ y.jsx("svg", { className: "ss-window__chev", width: "10", height: "10", viewBox: "0 0 10 10", "aria-hidden": !0, children: /* @__PURE__ */ y.jsx("path", { d: d ? "M6.5 1.5 3 5l3.5 3.5" : "M3.5 1.5 7 5 3.5 8.5", fill: "none", stroke: "currentColor", strokeWidth: "1.4", strokeLinecap: "round", strokeLinejoin: "round" }) });
}
function r0({ url: d, urlShape: w, tabs: f, nav: N, title: j, sidebar: C, sidebarWidth: V = 180, sidebarStyle: ee, toolbar: I, lead: ce, body: O, className: ie, receded: re, chrome: oe, lights: Z, lightsSize: te, barSize: q, children: we, ...Ne }) {
  const Me = `ss-window ss-recede${ie ? ` ${ie}` : ""}`, ve = te === "large" ? "large" : void 0, Oe = q === "tall" ? "tall" : void 0;
  if (oe === "terminal")
    return /* @__PURE__ */ y.jsxs("div", { ...Ne, className: Me, "data-chrome": "terminal", "data-lights": Z === "grey" ? "grey" : void 0, "data-lights-size": ve, "data-receded": re || void 0, children: [
      /* @__PURE__ */ y.jsxs("div", { className: "ss-window__bar", children: [
        /* @__PURE__ */ y.jsx(yl, {}),
        j !== void 0 && /* @__PURE__ */ y.jsx("span", { className: "ss-term__title", children: j })
      ] }),
      /* @__PURE__ */ y.jsx("div", { ...O, className: `ss-window__body ss-term${O != null && O.className ? ` ${O.className}` : ""}`, children: we })
    ] });
  if (oe === "glass" || oe === "card" || oe === "hairline")
    return /* @__PURE__ */ y.jsxs("div", { ...Ne, className: Me, "data-chrome": oe, "data-lights": Z === "color" || Z === "white" ? Z : oe === "glass" ? "grey" : void 0, "data-receded": re || void 0, children: [
      /* @__PURE__ */ y.jsxs("div", { className: "ss-window__bar", children: [
        /* @__PURE__ */ y.jsx(yl, {}),
        d !== void 0 && /* @__PURE__ */ y.jsxs("span", { className: "ss-window__url", children: [
          oe === "glass" && /* @__PURE__ */ y.jsx(n0, {}),
          /* @__PURE__ */ y.jsx("span", { className: "ss-window__url-text", children: d })
        ] }),
        /* @__PURE__ */ y.jsx("span", { className: "ss-window__end", children: I })
      ] }),
      /* @__PURE__ */ y.jsx("div", { ...O, className: `ss-window__body${O != null && O.className ? ` ${O.className}` : ""}`, children: we })
    ] });
  const Ie = d !== void 0 && /* @__PURE__ */ y.jsxs(y.Fragment, { children: [
    N && /* @__PURE__ */ y.jsxs("span", { className: "ss-window__nav", children: [
      /* @__PURE__ */ y.jsx(uc, { back: !0 }),
      /* @__PURE__ */ y.jsx(uc, {})
    ] }),
    /* @__PURE__ */ y.jsx("span", { className: "ss-window__url", children: d })
  ] });
  return C !== void 0 ? /* @__PURE__ */ y.jsxs("div", { ...Ne, className: Me, "data-kind": "sidebar", "data-side": ee === "floating" ? "floating" : void 0, "data-lights": Z === "grey" ? "grey" : void 0, "data-lights-size": ve, "data-bar": Oe, "data-receded": re || void 0, "data-url-shape": w, children: [
    /* @__PURE__ */ y.jsxs("aside", { className: "ss-window__side", style: { width: V }, children: [
      /* @__PURE__ */ y.jsx("div", { className: "ss-window__side-top", children: /* @__PURE__ */ y.jsx(yl, {}) }),
      C
    ] }),
    /* @__PURE__ */ y.jsxs("div", { className: "ss-window__main", children: [
      /* @__PURE__ */ y.jsxs("div", { className: "ss-window__bar", children: [
        j !== void 0 && /* @__PURE__ */ y.jsx("span", { className: "ss-window__heading", children: j }),
        ce,
        Ie,
        /* @__PURE__ */ y.jsx("span", { className: "ss-window__spacer" }),
        I
      ] }),
      /* @__PURE__ */ y.jsx("div", { ...O, className: `ss-window__body${O != null && O.className ? ` ${O.className}` : ""}`, children: we })
    ] })
  ] }) : f != null && f.length ? /* @__PURE__ */ y.jsxs("div", { ...Ne, className: Me, "data-kind": "tabs", "data-lights": Z === "grey" ? "grey" : void 0, "data-lights-size": ve, "data-receded": re || void 0, "data-url-shape": w, children: [
    /* @__PURE__ */ y.jsxs("div", { className: "ss-window__tabs", children: [
      /* @__PURE__ */ y.jsx(yl, {}),
      f.map((je, D) => /* @__PURE__ */ y.jsxs("span", { className: "ss-window__tab", "data-active": D === 0 || void 0, children: [
        /* @__PURE__ */ y.jsx("span", { className: "ss-window__favicon" }),
        /* @__PURE__ */ y.jsx("span", { className: "ss-window__tab-label", children: je })
      ] }, D))
    ] }),
    /* @__PURE__ */ y.jsxs("div", { className: "ss-window__bar", children: [
      Ie,
      I
    ] }),
    /* @__PURE__ */ y.jsx("div", { ...O, className: `ss-window__body${O != null && O.className ? ` ${O.className}` : ""}`, children: we })
  ] }) : /* @__PURE__ */ y.jsxs("div", { ...Ne, className: Me, "data-receded": re || void 0, "data-url-shape": w, "data-lights": Z === "grey" ? "grey" : void 0, "data-lights-size": ve, "data-bar": Oe, children: [
    /* @__PURE__ */ y.jsxs("div", { className: "ss-window__bar", children: [
      /* @__PURE__ */ y.jsx(yl, {}),
      Ie,
      j !== void 0 && /* @__PURE__ */ y.jsx("span", { className: "ss-window__title", "data-toolbar": I ? !0 : void 0, children: j }),
      ce,
      d === void 0 && j === void 0 && /* @__PURE__ */ y.jsx("span", { className: "ss-window__spacer" }),
      I
    ] }),
    /* @__PURE__ */ y.jsx("div", { ...O, className: `ss-window__body${O != null && O.className ? ` ${O.className}` : ""}`, children: we })
  ] });
}
const l0 = ["var(--ss-ink-1)", "var(--ss-ink-2)", "var(--ss-ink-3)", "var(--ss-ink-4)", "var(--ss-ink-5)"];
function i0({ w: d, h: w = 6, tone: f = 3, r: N = 2, shrink: j, className: C, style: V, ...ee }) {
  const I = j ?? (typeof d == "number" && d > w * 3);
  return /* @__PURE__ */ y.jsx("span", { ...ee, className: `ss-bar${C ? ` ${C}` : ""}`, "data-shrink": I || void 0, style: { width: d, height: w, borderRadius: N, background: l0[f - 1], ...V } });
}
function yu({ children: d, w, h: f = 6, tone: N = 3, wrap: j, filler: C, className: V, style: ee, ...I }) {
  const { fidelity: ce } = Jd();
  if (ce === "minimal" || C && ce !== "realistic") {
    const O = typeof (ee == null ? void 0 : ee.fontSize) == "number" ? ee.fontSize : 11;
    return /* @__PURE__ */ y.jsx(i0, { ...I, w: w ?? Math.round(d.length * O * 0.52), h: f, tone: N, className: V });
  }
  return /* @__PURE__ */ y.jsx("span", { ...I, className: `ss-text${V ? ` ${V}` : ""}`, "data-wrap": j || void 0, style: ee, children: d });
}
const o0 = { tool: "pointer", drawn: 0, copied: !1 }, u0 = { tool: "pointer", drawn: 1, copied: !0 }, s0 = document.documentElement.lang.startsWith("en"), tr = s0 ? {
  title: "Screenshot annotation",
  tag: "A LITTLE FIELD NOTE",
  headline: /* @__PURE__ */ y.jsxs(y.Fragment, { children: [
    "Good ideas.",
    /* @__PURE__ */ y.jsx("br", {}),
    "Room to grow."
  ] }),
  foot: "Worth a closer look.",
  copied: "Copied to clipboard",
  replay: "Replay demo",
  description: "Illustrated demo: select the rectangle tool, highlight the headline, then copy the screenshot."
} : {
  title: "截图标注",
  tag: "A LITTLE FIELD NOTE",
  headline: /* @__PURE__ */ y.jsxs(y.Fragment, { children: [
    "好点子，",
    /* @__PURE__ */ y.jsx("br", {}),
    "从这里开始。"
  ] }),
  foot: "让重点，一眼可见。",
  copied: "已复制到剪贴板",
  replay: "重播演示",
  description: "功能示意演示：选择矩形工具，框出标题，再复制截图。"
};
async function a0(d) {
  await d.wait(1100), await d.click("rectangle"), await d.set({ tool: "rectangle" }), d.mark("tool"), await d.wait(750), await d.cursor("crosshair");
  const w = d.rect("highlight");
  await d.move({ x: w.x, y: w.y }), await d.drag({ x: w.x + w.width, y: w.y + w.height }, (f) => d.put({ drawn: (f.x - w.x) / w.width }), {
    duration: 1200,
    cursor: "preserve",
    path: (f, N, j) => ({ x: N.x + (j.x - N.x) * f, y: N.y + (j.y - N.y) * f })
  }), d.mark("outlined"), await d.wait(1600), await d.cursor("pointer"), await d.click("pointer"), await d.set({ tool: "pointer" }), await d.wait(600), await d.click("copy"), await d.set({ copied: !0 }), d.mark("copied"), await d.wait(3e3);
}
function c0() {
  const [d, w] = W.useState(0), f = W.useRef(window.matchMedia("(prefers-reduced-motion: reduce)"));
  return /* @__PURE__ */ y.jsxs(y.Fragment, { children: [
    /* @__PURE__ */ y.jsx("span", { className: "demo-sr-only", children: tr.description }),
    /* @__PURE__ */ y.jsx("div", { "aria-hidden": "true", children: /* @__PURE__ */ y.jsx(
      t0,
      {
        width: 620,
        height: 480,
        compact: { below: 570, width: 358, height: 358 },
        initial: o0,
        poster: u0,
        script: a0,
        play: "once",
        fidelity: "realistic",
        cursor: { at: "rectangle", kind: "pointer", style: "real" },
        className: "sakura-demo",
        tokens: { "--ss-accent": "#b56383", "--ss-canvas": "#e3eaf1", "--ss-surface": "#f8fafc", "--ss-chrome": "#f8fafc", "--ss-text-strong": "#314b61", "--ss-text": "#60768b", "--ss-well": "transparent" },
        children: (N) => /* @__PURE__ */ y.jsxs(y.Fragment, { children: [
          /* @__PURE__ */ y.jsx(r0, { title: tr.title, className: "sakura-editor", toolbar: /* @__PURE__ */ y.jsx("span", { className: "demo-zoom", children: "100%" }), children: /* @__PURE__ */ y.jsxs("div", { className: "demo-canvas", children: [
            /* @__PURE__ */ y.jsxs("div", { className: "demo-paper", "data-cursor": N.tool === "rectangle" ? "crosshair" : "pointer", children: [
              /* @__PURE__ */ y.jsx(yu, { className: "demo-paper-tag", children: tr.tag }),
              /* @__PURE__ */ y.jsx("div", { className: "demo-headline", children: tr.headline }),
              /* @__PURE__ */ y.jsxs("svg", { className: "demo-art", viewBox: "0 0 176 202", "aria-hidden": "true", children: [
                /* @__PURE__ */ y.jsx("path", { d: "M0 88a88 88 0 0 1 176 0v114H0Z", fill: "#d7e4f0" }),
                /* @__PURE__ */ y.jsx("circle", { cx: "100", cy: "70", r: "45", fill: "#e4b0c1" }),
                /* @__PURE__ */ y.jsx("path", { d: "M0 118q90 14 176 80v4H0Z", fill: "#afc5d7" }),
                /* @__PURE__ */ y.jsx("path", { d: "M0 202q66-53 176-57v57Z", fill: "#6e8ca6" })
              ] }),
              /* @__PURE__ */ y.jsx(yu, { className: "demo-paper-foot", children: tr.foot }),
              /* @__PURE__ */ y.jsx("div", { className: "demo-highlight", "data-target": "highlight", children: /* @__PURE__ */ y.jsx("div", { style: { width: `${N.drawn * 100}%`, height: `${N.drawn * 100}%`, opacity: N.drawn > 0 ? 1 : 0 } }) })
            ] }),
            /* @__PURE__ */ y.jsxs("div", { className: "demo-toolbar", children: [
              [
                ["pointer", gd],
                ["pen", wd],
                ["arrow", md],
                ["rectangle", kd],
                ["ellipse", vd],
                ["text", Sd]
              ].map(([j, C]) => {
                const V = C;
                return /* @__PURE__ */ y.jsx("span", { className: "demo-tool", "data-target": j, "data-cursor": "pointer", "data-active": N.tool === j || void 0, children: /* @__PURE__ */ y.jsx(V, { size: 18, strokeWidth: 1.7 }) }, j);
              }),
              /* @__PURE__ */ y.jsx("span", { className: "demo-divider" }),
              /* @__PURE__ */ y.jsx("span", { className: "demo-tool demo-color" }),
              /* @__PURE__ */ y.jsx("span", { className: "demo-tool demo-undo", children: /* @__PURE__ */ y.jsx(Ed, { size: 18, strokeWidth: 1.7 }) }),
              /* @__PURE__ */ y.jsx("span", { className: "demo-divider" }),
              /* @__PURE__ */ y.jsxs("span", { className: "demo-tool demo-copy", "data-target": "copy", "data-cursor": "pointer", "data-copied": N.copied || void 0, children: [
                /* @__PURE__ */ y.jsx(yd, { size: 18, strokeWidth: 1.7, className: "demo-copy-icon" }),
                /* @__PURE__ */ y.jsx(tc, { size: 18, strokeWidth: 1.7, className: "demo-check-icon" })
              ] })
            ] })
          ] }) }),
          /* @__PURE__ */ y.jsxs("div", { className: "demo-confirmation", "data-show": N.copied || void 0, children: [
            /* @__PURE__ */ y.jsx("span", { className: "demo-confirm-icon", children: /* @__PURE__ */ y.jsx(tc, { size: 16, strokeWidth: 1.7 }) }),
            /* @__PURE__ */ y.jsx(yu, { children: tr.copied })
          ] })
        ] })
      },
      d
    ) }),
    /* @__PURE__ */ y.jsxs("button", { type: "button", className: "demo-replay", onClick: () => {
      f.current.matches || w((N) => N + 1);
    }, children: [
      /* @__PURE__ */ y.jsx(xd, { size: 13, strokeWidth: 1.7 }),
      tr.replay
    ] })
  ] });
}
const gu = document.getElementById("product-demo");
gu && (fd.createRoot(gu).render(/* @__PURE__ */ y.jsx(c0, {})), gu.classList.add("demo-mounted"));
