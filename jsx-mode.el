;;; jsx-mode.el --- major mode for JSX codes

;; Copyright (c) 2012 DeNA, Co., Ltd (http://dena.jp/intl/)

;; Author: Takeshi Arabiki (abicky)
;; Version: See `jsx-version'

;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be included in
;; all copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
;; THE SOFTWARE.

;;; Commentary:

;; Put this file in your Emacs lisp path (e.g. ~/.emacs.d/site-lisp)
;; and add to the following lines to your .emacs:

;;    (add-to-list 'auto-mode-alist '("\\.jsx\\'" . jsx-mode))
;;    (autoload 'jsx-mode "jsx-mode" "JSX mode" t)


;; TODO:
;; * anonymouse function calls is not indented correctly like below
;;    (function() : void {
;;            log "";
;;        })();
;; * support flymake
;; * support imenu

;;; Code:

(require 'thingatpt)

(defconst jsx-version "0.0.2"
  "Version of `jsx-mode'")

(defgroup jsx nil
  "JSX mode."
  :group 'languages)

(defcustom jsx-indent-level 4
  "indent level in `jsx-mode'"
  :type 'integer
  :group 'jsx-mode)

(defcustom jsx-cmd "jsx"
  "jsx command for `jsx-mode'"
  :type 'string
  :group 'jsx-mode)

(defcustom jsx-node-cmd "node"
  "node command for `jsx-mode'"
  :type 'string
  :group 'jsx-mode)

(defvar jsx-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") 'comment-region)
    (define-key map (kbd "C-c c") 'jsx-compile-file)
    (define-key map (kbd "C-c C-r") 'jsx-compile-file-and-run)
    map))

(defvar jsx-mode-syntax-table
  (let ((st (make-syntax-table)))
    ;; cf. Syntax Tables > Syntax Descriptors > Syntax Flags
    (modify-syntax-entry ?/  ". 124b" st)
    (modify-syntax-entry ?*  ". 23"   st)
    (modify-syntax-entry ?\n "> b"  st)
    st))



;; Constant variables
(defconst jsx--constant-variables
  '("__FILE__" "__LINE__"
    "Infinity"
    "NaN"
    "false"
    "null"
    "this" "true"
    "undefined"))

(defconst jsx--keywords
  '(;; literals shared with ECMA 262literals shared with ECMA 262
    "null"      "true"       "false"
    "NaN"       "Infinity"
    ;; keywords shared with ECMA 262
    "break"     "do"         "instanceof" "typeof"
    "case"      "else"       "new"        "var"
    "catch"     "finally"    "return"     "void"
    "continue"  "for"        "switch"     "while"
    "function"  "this"
    "default"   "if"         "throw"
    "delete"    "in"         "try"
    ;; keywords of JSX
    "class"     "extends"    "super"
    "import"    "implements"
    "interface" "static"
    "__FILE__"  "__LINE__"
    "undefined")
  "keywords defined in parser.js of JSX")

(defconst jsx--reserved-words
  '(;; literals of ECMA 262 but not used by JSX
    "debugger"  "with"
    ;; future reserved words of ECMA 262
    "const"     "export"
    ;; future reserved words within strict mode of ECMA 262
    "let"       "private"     "public"     "yield"
    "protected"
    ;; JSX specific reserved words
    "extern"    "native"
    "trait"     "using"
    "as"        "is"
    "operator"  "package")
  "reserved words defined in parser.js of JSX")

(defconst jsx--contextual-keywords
  '("__noconvert__" "__readonly__" "abstract" "final" "mixin" "override"))

(defconst jsx--builtin-functions
  '("assert" "log"))

(defconst jsx--primary-types
  '("boolean" "int" "number" "string"))

(defconst jsx--extra-types
  '("MayBeUndefined" "void" "variant"))

(defconst jsx--reserved-classes
  '("Array"
    "Boolean"
    "Date"
    "Error" "EvalError"
    "Function"
    "Map"
    "Number"
    "Object"
    "RangeError" "ReferenceError" "RegExp"
    "String" "SyntaxError"
    "TypeError"))

(defconst jsx--template-owners
  '("Array" "Map" "MayBeUndefined"))

(defconst jsx--modifiers
  '("static" "abstract" "override" "final" "const" "native" "__readonly__"))

(defconst jsx--class-definitions
  '("class" "extends" "implements" "interface" "mixin"))



;; Regural expressions
(defconst jsx--identifier-start-re
  "[a-zA-Z_]")

(defconst jsx--identifier-re
  (concat jsx--identifier-start-re "[a-zA-Z0-9_]*"))

(defconst jsx--function-definition-re
  (concat
   "^\\s-*\\(?:\\(?:" (mapconcat 'identity jsx--modifiers "\\|") "\\)\\s-+\\)*"
   "function\\s-+\\(" jsx--identifier-re "\\)"))

(defconst jsx--function-definition-in-map-re
  (concat
   "\\(?:^\\|,\\)\\s-*\\(" jsx--identifier-re "\\)\\s-*:\\s-*function\\s-*("))

(defconst jsx--keywords-re
  ;; not match __noconvert__ if specify 'words to the 2nd argument of regex-opt
  (concat
   "\\_<"
   (regexp-opt
    (append jsx--keywords jsx--reserved-words jsx--contextual-keywords))
   "\\_>"))

(defconst jsx--constant-variable-re
  ;; not match __FILE__ if specify 'words to the 2nd argument of regex-opt
  (concat
   "\\_<"
  (regexp-opt jsx--constant-variables)
  "\\_>"))

(defconst jsx--primitive-type-re
  (regexp-opt
   (append jsx--primary-types jsx--extra-types jsx--template-owners)
   'words))

(defconst jsx--reserved-class-re
  (concat
   "\\<\\("
   (regexp-opt jsx--reserved-classes)
   "\\)\\s-*[,;>(]"))

(defconst jsx--regex-literal-re
  (concat
   "\\(?:^\\|[(,;:]\\)\\s-*"
   "\\(/[^/\\]*\\(?:\\\\.[^/\\]*\\)*/[gim]*\\)"))

(defconst jsx--builtin-function-re
  (concat
   "\\(?:^\\|[;{]\\)\\s-*\\("
   (regexp-opt jsx--builtin-functions 'words)
   "\\)"))

(defconst jsx--class-definition-re
      (concat
       (regexp-opt jsx--class-definitions 'words)
       "\\s-+\\(" jsx--identifier-re "\\)"))

(defconst jsx--create-instance-re
      (concat
       "\\<new\\s-+"
       ;; call 'new foo.Foo' to create a Foo class instance defined in foo.jsx
       ;; if import "foo.jsx" into foo
       "\\(?:" jsx--identifier-re "\\.\\)?"
       "\\(" jsx--identifier-re "\\)"))

(defconst jsx--template-class-re
  (concat "<\\s-*\\(" jsx--identifier-re "\\)\\s-*>"))

;; currently not support definitions like 'var a:int, b:int;'
(defconst jsx--variable-definition-re
  (concat
   "\\<\\var\\s-+\\(" jsx--identifier-re "\\)\\>"))



(defun jsx--in-arg-definition-p ()
  (when (list-at-point)
    (save-excursion
      (search-backward "(")
      (forward-symbol -1)
      (or (equal (word-at-point) "function")
          (progn (forward-symbol -1)
                 (equal (word-at-point) "function"))))))


(defvar jsx-font-lock-keywords
  `(
    (,jsx--constant-variable-re 0 font-lock-constant-face)
    (,jsx--builtin-function-re 0 font-lock-builtin-face)
    (,jsx--regex-literal-re 1 font-lock-string-face)
    (,jsx--variable-definition-re 1 font-lock-variable-name-face)
    (,jsx--primitive-type-re 0 font-lock-type-face)
    (,jsx--reserved-class-re 1 font-lock-type-face)
    (,jsx--keywords-re 0 font-lock-keyword-face)
    (,jsx--class-definition-re 2 font-lock-type-face)
    (,jsx--create-instance-re 1 font-lock-type-face)
    (,jsx--template-class-re  1 font-lock-type-face)
    (,jsx--function-definition-re 1 font-lock-function-name-face)
    (,jsx--function-definition-in-map-re 1 font-lock-function-name-face)

    ;; color names of interface or mixin like implements A, B, C
    ,(list
      "\\(?:^\\|\\s-\\)implements\\s-+"
      (list (concat "\\(" jsx--identifier-re "\\)\\s-*\\(?:[,{]\\|$\\)")
            '(forward-symbol -1)
            nil
            '(1 font-lock-type-face)))

    ;; color class name of the return value like function createFoo() : Foo {
    (,(concat ")\\s-*:\\s-*\\(" jsx--identifier-re "\\)") 1 font-lock-type-face)

    ;; color class names like below (color 'B', 'I', and 'J')
    ;;     class A
    ;;     extends B
    ;;     implements I, J {
    ;;
    ;; currently not color names like below  (not color 'J')
    ;;     class A
    ;;     extends B
    ;;    implements I,
    ;;     J {
    ,(list
      (concat
        "^\\s-*\\(" jsx--identifier-re "\\)\\(?:\\s-\\|$\\)")
      (list (concat "\\<" jsx--identifier-re "\\>")
            '(if (save-excursion
                   (backward-word 2)
                   (looking-at (concat
                                (regexp-opt jsx--class-definitions)
                                "\\s-*$")))
                 (backward-word)
               (end-of-line))
            nil
            '(0 font-lock-type-face)))

    ;; color function arguments like function(a: int, b:int)
    ,(list
      (concat
       "\\<function\\>\\(?:\\s-+" jsx--identifier-re "\\)?\\s-*(\\s-*")
      (list (concat "\\(" jsx--identifier-re "\\)\\s-*:\\s-*\\(" jsx--identifier-re "\\)")
            '(unless (jsx--in-arg-definition-p) (end-of-line))
            nil
            '(1 font-lock-variable-name-face)
            '(2 font-lock-type-face)))
    (,(concat "<\\s-*\\(" jsx--identifier-re "\\)\\s-*>") 1 font-lock-type-face)

    ;; color classes of function arugments like function(:int, :int)
    ,(list
     (concat
      "\\<function\\>\\s-*(\\s-*")
     (list (concat "\\s-*:\\s-*\\(" jsx--identifier-re "\\)")
           '(unless (jsx--in-arg-definition-p) (end-of-line))
           nil
           '(1 font-lock-type-face)))

    ;; color function arguments
    ;;     function(a: int,
    ;;              b:int)
    ;;
    ;; currently not color arguments like below
    ;;     function(a:
    ;;              int,
    ;;              b
    ;;              :int)
    ,(list
      (concat
       "^\\s-*,?\\s-*\\(" jsx--identifier-re "\\)\\s-*:\\s-*\\(" jsx--identifier-re "\\)")
      (list (concat "\\(" jsx--identifier-re "\\)\\s-*:\\s-*\\(" jsx--identifier-re "\\)")
            '(if (save-excursion (backward-char)
                                 (jsx--in-arg-definition-p))
                 (forward-symbol -2)
               (end-of-line))
            nil
            '(1 font-lock-variable-name-face)
            '(2 font-lock-type-face)))

    ;; color classes of function arguments like below
    ;;     function(:int,
    ;;              :int)
    ;;
    ;; currently not color classes like below
    ;;     function(:
    ;;              int,
    ;;              :int)
    ,(list
      (concat
       "^\\s-*,?\\s-*:\\s-*\\(" jsx--identifier-re "\\)")
      (list (concat "\\s-*:\\s-*\\(" jsx--identifier-re "\\)")
            '(if (save-excursion (backward-char)
                                 (jsx--in-arg-definition-p))
                 (search-backward ":")
               (end-of-line))
            nil
            '(1 font-lock-type-face)))
    ))


(defun jsx--in-string-or-comment-p (&optional pos)
  (nth 8 (syntax-ppss pos)))


(defun jsx--calculate-depth (&optional pos)
  (save-excursion
    (let ((depth (nth 0 (syntax-ppss pos))))
      ;; TODO
      depth)))

(defun jsx-indent-line ()
  (interactive)
  (let ((indent-length (jsx-calculate-indentation))
        (offset (- (current-column) (current-indentation))))
    (when indent-length
      (indent-line-to indent-length)
      (if (> offset 0) (forward-char offset)))))

(defun jsx-calculate-indentation (&optional pos)
  (save-excursion
    (if pos
        (goto-char pos)
      (back-to-indentation))
    (let* ((cw (current-word))
           (ca (char-after))
           (depth (jsx--calculate-depth)))
      (if (or (eq ca ?})
              (eq ca ?\))
              (equal cw "case")
              (equal cw "default"))
          (setq depth (1- depth)))
      (cond
       ((jsx--in-string-or-comment-p) nil)
       (t (* jsx-indent-level depth))
       ))))

(defun jsx-compile-file (&optional options dst)
  "Compile the JSX script of the current buffer
and make a JS script in the same directory."
  (interactive)
  ;; TODO: save another temporary file or popup dialog to ask whether or not to save
  (save-buffer)
  ;; FIXME: file-name-nondirectory needs temporarily
  (let* ((jsx-file (file-name-nondirectory (buffer-file-name)))
         (js-file (or dst (substring jsx-file 0 -1)))
         cmd)
    (if options
        (setq cmd (format "%s %s --output %s %s" jsx-cmd options js-file jsx-file))
      (setq cmd (format "%s --output %s %s" jsx-cmd js-file jsx-file)))
    (message "Compiling...")
    (message cmd)
    (if (eq (shell-command cmd) 0) js-file nil)))


;; TODO: if JS file already exits, run the script even though the compilcation failed
(defun jsx-compile-file-and-run ()
  "Compile the JSX script of the current buffer,
make a JS script in the same directory, and run it."
  (interactive)
  (let* ((js-file (jsx-compile-file "--executable"))
         (cmd (format "%s %s" jsx-node-cmd js-file)))
    (if js-file
        (shell-command cmd))))


(define-derived-mode jsx-mode fundamental-mode "Jsx"
  :syntax-table jsx-mode-syntax-table
  (set (make-local-variable 'font-lock-defaults)
       '(jsx-font-lock-keywords nil nil))
  (set (make-local-variable 'indent-line-function) 'jsx-indent-line)
  (set (make-local-variable 'comment-start) "// ")
  (set (make-local-variable 'comment-end) ""))

(provide 'jsx-mode)