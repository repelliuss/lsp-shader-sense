;;; lsp-shader-sense.el --- lsp-mode client for shader-sense -*- lexical-binding: t; -*-

;; Author: Sami Batuhan Basmaz Olmez <repelliuss@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (lsp-mode "9.0"))
;; Keywords: languages lsp hlsl glsl shader
;; URL: https://github.com/repelliuss/lsp-shader-sense
;; SPDX-License-Identifier: GPL-3.0-or-later

;;; Commentary:

;; lsp-mode client for the shader-sense language server
;; (https://github.com/antaalt/shader-sense).
;;
;; Registers `shader-language-server' as an lsp-mode client for HLSL and
;; GLSL buffers.  By default `hlsl-ts-mode' is activated automatically;
;; additional major modes can be added via `lsp-shader-sense-modes'.
;;
;; All settings are exposed as `lsp-defcustom' variables so that live
;; `setopt'/customize changes trigger a `DidChangeConfiguration' notification
;; and the server picks them up without a restart.
;;
;; Activate via `lsp-shader-sense-setup' or the minor mode
;; `lsp-shader-sense-mode'.  Project-specific configuration (include paths,
;; defines, etc.) is best handled via `.dir-locals.el'.
;;
;; If `shader-language-server' is not already on `exec-path', run
;; `M-x lsp-install-server RET shader-sense RET' to download the latest
;; release for your platform (Linux and Windows only; other platforms
;; must build and set `lsp-shader-sense-executable' manually).

;;; Code:

(require 'lsp-mode)

(defgroup lsp-shader-sense nil
  "lsp-mode client for the shader-sense language server."
  :group 'lsp-mode
  :prefix "lsp-shader-sense-"
  :link '(url-link "https://github.com/antaalt/shader-sense"))

;;; Connection

(defcustom lsp-shader-sense-executable nil
  "Path to the shader-sense `shader-language-server' executable.
When nil, the executable is located automatically: first via
`executable-find' on `exec-path', then via `lsp-install-server' if a
copy was previously downloaded."
  :type '(choice (const :tag "Auto-detect" nil) file)
  :group 'lsp-shader-sense)

(defun lsp-shader-sense--find-executable ()
  "Return `lsp-shader-sense-executable', or locate it via `executable-find'."
  (or lsp-shader-sense-executable
      (executable-find "shader-language-server")
      (executable-find "shader-language-server.exe")))

(defcustom lsp-shader-sense-args '("--stdio")
  "Arguments passed to `lsp-shader-sense-executable'."
  :type '(repeat string)
  :group 'lsp-shader-sense)

;;; Installation

(defcustom lsp-shader-sense-version "latest"
  "Version of shader-language-server to install via `lsp-install-server'.
Either \"latest\" to always fetch the newest GitHub release, or an
explicit release tag such as \"v1.5.0\"; see
https://github.com/antaalt/shader-sense/releases for available tags."
  :type '(choice (const :tag "Latest" "latest")
                 string)
  :group 'lsp-shader-sense)

(defvar lsp-shader-sense--download-url-cache nil
  "Cached download URL for the shader-language-server release asset.")

(defun lsp-shader-sense--asset-name ()
  "Return the release asset filename for the current platform."
  (concat "shader-language-server-"
          (pcase (list system-type (lsp-resolve-value lsp--system-arch))
            (`(gnu/linux  x64)   "x86_64-unknown-linux-gnu")
            (`(windows-nt x64)   "x86_64-pc-windows-msvc")
            (`(windows-nt arm64) "aarch64-pc-windows-msvc")
            (_ (user-error
                "shader-sense does not publish a prebuilt %s/%s server; install `shader-language-server' manually and set `lsp-shader-sense-executable'"
                system-type (lsp-resolve-value lsp--system-arch))))
          ".zip"))

(defun lsp-shader-sense--download-url ()
  "Return the download URL of the shader-language-server release to install.
When `lsp-shader-sense-version' is \"latest\", queries the GitHub
releases API for the newest release; otherwise builds the URL for
that release tag directly, without any network request."
  (setq lsp-shader-sense--download-url-cache
        (if (equal lsp-shader-sense-version "latest")
            (lsp--find-latest-gh-release-url
             "https://api.github.com/repos/antaalt/shader-sense/releases/latest"
             (concat (regexp-quote (lsp-shader-sense--asset-name)) "\\'"))
          (format "https://github.com/antaalt/shader-sense/releases/download/%s/%s"
                  lsp-shader-sense-version
                  (lsp-shader-sense--asset-name)))))

(defun lsp-shader-sense--server-dir ()
  "Directory shader-language-server and its runtime libraries live in."
  (f-join lsp-server-install-dir "shader-sense"))

(defun lsp-shader-sense--store-path ()
  "Path the downloaded archive is decompressed from.
`lsp-download-install' decompresses a `:zip' archive into the parent
of this path, i.e. `lsp-shader-sense--server-dir'; this path itself is
only used to derive the `.zip' download location."
  (f-join (lsp-shader-sense--server-dir) "shader-language-server-archive"))

(defun lsp-shader-sense--binary-path ()
  "Path to the `shader-language-server' executable once downloaded.
The archive also contains shared libraries (`libdxcompiler', `libdxil')
that the server loads at runtime, so the whole archive is extracted
alongside the executable rather than extracting it alone."
  (f-join (lsp-shader-sense--server-dir)
          (if (eq system-type 'windows-nt)
              "shader-language-server.exe"
            "shader-language-server")))

(lsp-dependency
 'shader-sense
 '(:system lsp-shader-sense--find-executable)
 '(:download :url lsp-shader-sense--download-url
             :store-path lsp-shader-sense--store-path
             :decompress :zip
             :binary-path lsp-shader-sense--binary-path
             :set-executable? t))

;;; Major-mode activation

(defcustom lsp-shader-sense-modes '(hlsl-ts-mode)
  "Major modes for which shader-sense is activated automatically.
Each entry is registered in `lsp-language-id-configuration' when
`lsp-shader-sense-mode' is enabled."
  :type '(repeat symbol)
  :group 'lsp-shader-sense)

(defcustom lsp-shader-sense-language-id "hlsl"
  "Language identifier sent to shader-sense for all registered modes."
  :type 'string
  :group 'lsp-shader-sense)

;;; Top-level server settings

(lsp-defcustom lsp-shader-sense-includes []
  "Vector of include directories sent to shader-language-server."
  :type '(lsp-repeatable-vector directory)
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.includes")

(lsp-defcustom lsp-shader-sense-defines nil
  "Alist of preprocessor defines sent to shader-language-server.
Each element is (NAME . VALUE).  Keys must be symbols."
  :type '(alist :key-type (symbol :tag "Name") :value-type (string :tag "Value"))
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.defines")

(lsp-defcustom lsp-shader-sense-path-remapping nil
  "Alist mapping virtual paths to real paths on disk.
Each element is (VIRTUAL-PATH . REAL-PATH).  Keys must be symbols."
  :type '(alist :key-type (symbol :tag "Virtual path") :value-type (string :tag "Real path"))
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.pathRemapping")

(lsp-defcustom lsp-shader-sense-validate t
  "Non-nil to enable shader validation via the language-specific API."
  :type 'boolean
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.validate")

(lsp-defcustom lsp-shader-sense-symbols t
  "Non-nil to enable symbol queries (completion, hover, goto)."
  :type 'boolean
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.symbols")

(lsp-defcustom lsp-shader-sense-symbol-diagnostics nil
  "Non-nil to surface tree-sitter symbol-parsing issues as diagnostics.
This is a debug option; leave nil in normal use."
  :type 'boolean
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.symbolDiagnostics")

(lsp-defcustom lsp-shader-sense-dependency-context-diagnostics nil
  "Non-nil to reuse a dependent main-file context for document diagnostics."
  :type 'boolean
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.dependencyContextDiagnostics")

(lsp-defcustom lsp-shader-sense-experimental-macro-expansion t
  "Non-nil to enable experimental macro-expansion support."
  :type 'boolean
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.experimentalMacroExpansion")

(lsp-defcustom lsp-shader-sense-severity nil
  "Minimum diagnostic severity to display.
One of \"error\", \"warning\", \"info\", or \"hint\".
Nil means the server default (\"error\")."
  :type '(choice (const :tag "Server default" nil)
                 (const :tag "Error"   "error")
                 (const :tag "Warning" "warning")
                 (const :tag "Info"    "info")
                 (const :tag "Hint"    "hint"))
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.severity")

(lsp-defcustom lsp-shader-sense-config-override nil
  "Path to a JSON file that overrides shader-language-server configuration.
Nil means no override."
  :type '(choice (const :tag "None" nil) file)
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.configOverride")

;;; HLSL settings

(lsp-defcustom lsp-shader-sense-hlsl-shader-model "ShaderModel6_8"
  "HLSL shader model sent to DXC.  Nil means server default (ShaderModel6_8).
Values are the Rust enum variant names used by shader-sense."
  :type '(choice (const :tag "Server default" nil)
                 (const :tag "SM 1.0" "ShaderModel1")
                 (const :tag "SM 1.1" "ShaderModel1_1")
                 (const :tag "SM 1.2" "ShaderModel1_2")
                 (const :tag "SM 1.3" "ShaderModel1_3")
                 (const :tag "SM 1.4" "ShaderModel1_4")
                 (const :tag "SM 2.0" "ShaderModel2")
                 (const :tag "SM 3.0" "ShaderModel3")
                 (const :tag "SM 4.0" "ShaderModel4")
                 (const :tag "SM 4.1" "ShaderModel4_1")
                 (const :tag "SM 5.0" "ShaderModel5")
                 (const :tag "SM 5.1" "ShaderModel5_1")
                 (const :tag "SM 6.0" "ShaderModel6")
                 (const :tag "SM 6.1" "ShaderModel6_1")
                 (const :tag "SM 6.2" "ShaderModel6_2")
                 (const :tag "SM 6.3" "ShaderModel6_3")
                 (const :tag "SM 6.4" "ShaderModel6_4")
                 (const :tag "SM 6.5" "ShaderModel6_5")
                 (const :tag "SM 6.6" "ShaderModel6_6")
                 (const :tag "SM 6.7" "ShaderModel6_7")
                 (const :tag "SM 6.8" "ShaderModel6_8"))
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.hlsl.shaderModel")

(lsp-defcustom lsp-shader-sense-hlsl-version "V2021"
  "HLSL language version.  Nil means server default (V2021)."
  :type '(choice (const :tag "Server default" nil)
                 (const :tag "HLSL 2016" "V2016")
                 (const :tag "HLSL 2017" "V2017")
                 (const :tag "HLSL 2018" "V2018")
                 (const :tag "HLSL 2021" "V2021"))
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.hlsl.version")

(lsp-defcustom lsp-shader-sense-hlsl-enable-16bit-types t
  "Non-nil to enable 16-bit types in HLSL."
  :type 'boolean
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.hlsl.enable16bitTypes")

(lsp-defcustom lsp-shader-sense-hlsl-spirv nil
  "Non-nil to target SPIR-V output when compiling HLSL."
  :type 'boolean
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.hlsl.spirv")

;;; GLSL settings

(lsp-defcustom lsp-shader-sense-glsl-target-client nil
  "GLSL target client passed to glslang.  Nil means server default (Vulkan1_3)."
  :type '(choice (const :tag "Server default"  nil)
                 (const :tag "Vulkan 1.0"  "Vulkan1_0")
                 (const :tag "Vulkan 1.1"  "Vulkan1_1")
                 (const :tag "Vulkan 1.2"  "Vulkan1_2")
                 (const :tag "Vulkan 1.3"  "Vulkan1_3")
                 (const :tag "OpenGL 4.50" "OpenGL450"))
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.glsl.targetClient")

(lsp-defcustom lsp-shader-sense-glsl-spirv-version nil
  "GLSL SPIR-V target version.  Nil means server default (SPIRV1_6)."
  :type '(choice (const :tag "Server default" nil)
                 (const :tag "SPIR-V 1.0" "SPIRV1_0")
                 (const :tag "SPIR-V 1.1" "SPIRV1_1")
                 (const :tag "SPIR-V 1.2" "SPIRV1_2")
                 (const :tag "SPIR-V 1.3" "SPIRV1_3")
                 (const :tag "SPIR-V 1.4" "SPIRV1_4")
                 (const :tag "SPIR-V 1.5" "SPIRV1_5")
                 (const :tag "SPIR-V 1.6" "SPIRV1_6"))
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.glsl.spirvVersion")

(lsp-defcustom lsp-shader-sense-glsl-preamble nil
  "Path to a GLSL preamble file prepended to every GLSL source before validation.
Nil means no preamble."
  :type '(choice (const :tag "None" nil) file)
  :group 'lsp-shader-sense
  :lsp-path "shader-validator.glsl.preamble")

;;; Client registration

(defconst lsp-shader-sense--server-id 'shader-sense
  "lsp-mode server-id for the shader-sense client.")

(defconst lsp-shader-sense--section "shader-validator"
  "Configuration section shader-language-server pulls its settings from.")

(defun lsp-shader-sense--push-configuration (workspace)
  "Send the current shader-sense settings to WORKSPACE.
shader-language-server ignores `initializationOptions'; it only picks up
settings when it pulls them via `workspace/configuration'.  Since 1.4 it
only pulls on `didChangeConfiguration', so the initial configuration has
to be pushed explicitly once the workspace is initialized.  Settings are
read in a workspace buffer so buffer-local values, for example ones from
`.dir-locals.el', are honored."
  (lsp-with-current-buffer (or (--first (lsp-buffer-live-p it)
                                       (lsp--workspace-buffers workspace))
                               (current-buffer))
    (with-lsp-workspace workspace
      (lsp--set-configuration
       (lsp-configuration-section lsp-shader-sense--section)))))

(defun lsp-shader-sense--register ()
  "Register the shader-sense lsp-mode client."
  (dolist (mode lsp-shader-sense-modes)
    (add-to-list 'lsp-language-id-configuration
                 (cons mode lsp-shader-sense-language-id)))
  (lsp-register-client
   (make-lsp-client
    :new-connection (lsp-stdio-connection
                     (lambda ()
                       (cons (or (lsp-package-path 'shader-sense)
                                 (lsp-shader-sense--find-executable))
                             lsp-shader-sense-args)))
    :activation-fn (lsp-activate-on lsp-shader-sense-language-id)
    :synchronize-sections (list lsp-shader-sense--section)
    :initialized-fn #'lsp-shader-sense--push-configuration
    :download-server-fn (lambda (_client callback error-callback _update?)
                           (lsp-package-ensure 'shader-sense callback error-callback))
    :server-id lsp-shader-sense--server-id)))

(defun lsp-shader-sense--unregister ()
  "Remove the shader-sense lsp-mode client."
  ;; `lsp-clients' is a hash table keyed by server-id in lsp-mode 9+.
  (remhash lsp-shader-sense--server-id lsp-clients)
  (remhash (intern (concat (symbol-name lsp-shader-sense--server-id) "-tramp"))
           lsp-clients)
  (dolist (mode lsp-shader-sense-modes)
    (setq lsp-language-id-configuration
          (delete (cons mode lsp-shader-sense-language-id)
                  lsp-language-id-configuration))))

(lsp-shader-sense--register)

(provide 'lsp-shader-sense)
;;; lsp-shader-sense.el ends here
