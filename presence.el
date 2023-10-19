;;; presence.el --- Allows you to seamlessly integrate Emacs with Discord's Rich Presence feature

;; Copyright (C) 2023 richardhbtz

;; Author: richardhbtz
;;      Richard Habitzreuter <richardhabitzreuter@icloud.com>
;; Created: 15 Oct 2023
;; Version: 1.0.0
;; Keywords: games
;; Homepage: https://github.com/richardhbtz/emacs-presence
;; Package-Requires: ((emacs "29.1"))
;; License: MIT

;;; Commentary:
;; The "presence" package allows you to seamlessly integrate Emacs with Discord's Rich Presence feature.
;; When you enable the global minor mode `presence-mode', this package communicates with your local Discord client
;; to showcase information under the 'Playing a Game' status. It updates this information at regular intervals.
;; `presence-display-buffer-details' can be customized so that buffer name and line number are omitted.

;;; Code:

(require 'bindat)
(require 'cl-lib)
(require 'json)
(require 'subr-x)

(defgroup presence nil
  "Options for presence."
  :prefix "presence-"
  :group 'external)

(defcustom presence-client-id '"1163336687217287250"
  "ID of presence client (Application ID).
See <https://discordapp.com/developers/applications/me>."
  :type '(choice (const :tag "'Native' Application ID" "1163336687217287250")
                 (string :tag "Use the specified ID")
                 (function :tag "Call the function with no args to get the ID."))
  :group 'presence)

(defcustom presence-icon-base
  '"https://raw.githubusercontent.com/richardhbtz/emacs-presence/master/icons/"
  "Base URL for icon images. Mode icons will be loaded from this URL + the icon name + '.png'"
  :type '(choice (const :tag "Presence GitHub Repository"
                        "https://raw.githubusercontent.com/richardhbtz/emacs-presence/master/icons/")
                 (string :tag "Use the specified URL base")
                 (function :tag "Call the function with icon name as an arg to get the URL base."))
  :group 'presence)

(defcustom presence-refresh-rate 15
  "How often to send updates to Discord, in seconds."
  :type 'integer
  :group 'presence)

(defcustom presence-idle-timer 300
  "How long to wait before setting the status to idle."
  :type 'integer
  :group 'presence)

(defcustom presence-idle-message "Getting something to drink..."
  "Message to show when presence status is idle."
  :type 'string)

(defcustom presence-quiet 'nil
  "Whether or not to supress presence messages (connecting, disconnecting, etc.)"
  :type 'boolean
  :group 'presence)

(defcustom presence-mode-icon-alist '(
                                    (assembly-mode . "assembly")
                                    (c-mode . "c")
                                    (c++-mode . "cpp")
                                    (clojure-mode . "clojure")
                                    (csharp-mode . "csharp")
                                    (dockerfile-mode . "docker")
                                    (elixir-mode . "elixir")
                                    (emacs-lisp-mode . "emacs")
                                    (enh-ruby-mode . "ruby")
                                    (erlang-mode . "erlang")
                                    (fortran-mode . "fortran")
                                    (fsharp-mode . "fsharp")
                                    (gdscript-mode . "godot")
                                    (haskell-mode . "haskell")
                                    (java-mode . "jar")
                                    (julia-mode . "julia")
                                    (js-mode . "js")
                                    (kotlin-mode . "kotlin")
                                    (go-mode . "go")
                                    (lisp-mode . "lisp")
                                    (lua-mode . "lua")
                                    (magit-mode . "git")
                                    (markdown-mode . "markdown")
                                    (nim-mode . "nim")
                                    (nix-mode . "nix")
                                    (ocaml-mode . "ocaml")
                                    (org-mode . "org")
                                    (pdf-view-mode . "pdf")
                                    (pascal-mode . "pascal")
                                    (php-mode . "php")
                                    (python-mode . "python")
                                    (racket-mode . "racket")
                                    (ruby-mode . "ruby")
                                    (rust-mode . "rust")
                                    (rustic-mode . "rust")
                                    (scala-mode . "scala")
                                    (solidity-mode . "solidity")
                                    (sh-mode . "shell")
                                    (eshell-mode . "shell")
                                    (terraform-mode . "terraform")
                                    (typescript-mode . "ts")
                                    (zig-mode . "zig")
                                    ("^slime-.*" . "lisp-mode_icon")
                                    ("^sly-.*$" . "lisp-mode_icon"))
  "Mapping alist of major modes to icon names to have presence use.
Note, these icon names must be available as 'small_image' in Discord."
  :type '(alist :key-type (choice (symbol :tag "Mode name")
                                  (regexp :tag "Regex"))
                :value-type (choice (string :tag "Icon name")
                                    (function :tag "Mapping function")))
  :group 'presence)

(defcustom presence-mode-text-alist '((agda-mode . "Agda")
                                    (assembly-mode . "Assembly")
                                    (bqn-mode . "BQN")
                                    (c-mode . "C  ")
                                    (c++-mode . "C++")
                                    (csharp-mode . "C#")
                                    (cperl-mode . "Perl")
                                    (elixir-mode . "Elixir")
                                    (enh-ruby-mode . "Ruby")
                                    (erlang-mode . "Erlang")
                                    (fsharp-mode . "F#")
                                    (gdscript-mode . "GDScript")
                                    (hy-mode . "Hy")
                                    (java-mode . "Java")
                                    (julia-mode . "Julia")
                                    (lisp-mode . "Common Lisp")
                                    (markdown-mode . "Markdown")
                                    (org-mode . "Org")
                                    (pdf-view-mode . "PDF")
                                    (magit-mode . "Magit")
                                    ("mhtml-mode" . "HTML")
                                    (nim-mode . "Nim")
                                    (ocaml-mode . "OCaml")
                                    (pascal-mode . "Pascal")
                                    (prolog-mode . "Prolog")
                                    (puml-mode . "UML")
                                    (scala-mode . "Scala")
                                    (sh-mode . "Shell")
                                    (eshell-mode . "EShell")
                                    (slime-repl-mode . "SLIME-REPL")
                                    (sly-mrepl-mode . "Sly-REPL")
                                    (solidity-mode . "Solidity")
                                    (terraform-mode . "Terraform")
                                    (typescript-mode . "Typescript")
                                    (php-mode "PHP"))
  "Mapping alist of major modes to text labels to have presence use."
  :type '(alist :key-type (choice (symbol :tag "Mode name")
                                  (regexp :tag "Regex"))
                :value-type (choice (string :tag "Text label")
                                    (function :tag "Mapping function")))
  :group 'presence)

(defcustom presence-display-elapsed 't
  "When enabled, Discord status will display the elapsed time since Emacs \
has been started."
  :type 'boolean
  :group 'presence)

(defvar presence--startup-time (string-to-number (format-time-string "%s" (current-time))))

(defcustom presence-display-buffer-details 't
  "When enabled, Discord status will display buffer name and line numbers:
\"Editing <buffer-name>\"
  \"Line <line-number> (<line-number> of <line-count>)\"

Otherwise, it will display:
  \"Editing\"
  \"<presence-mode-text>\"

The mode text is the same found by `presence-mode-text-alist'"
  :type 'boolean
  :group 'presence)

(defcustom presence-display-line-numbers 't
  "When enabled, shows the total line numbers of current buffer.
Including the position of the cursor in the buffer."
  :type 'boolean
  :group 'presence)

(defcustom presence-buffer-details-format-function 'presence-buffer-details-format
  "Function to return the buffer details string shown on discord.
Swap this with your own function if you want a custom buffer-details message."
  :type 'function
  :group 'presence)

(defcustom presence-use-major-mode-as-main-icon 'nil
  "When enabled, the major mode determines the main icon, rather than it being the editor."
  :type 'boolean
  :group 'presence)

(defcustom presence-show-small-icon 't
  "When enabled, show the small icon as well as the main icon."
  :type 'boolean
  :group 'presence)

(defcustom presence-editor-icon 'nil
  "Icon to use for the text editor. When nil, use the editor's native icon."
  :type '(choice (const :tag "Editor Default" nil)
                 (const :tag "Emacs" "emacs")
                 (const :tag "Doom" "doomemacs")
                 (const :tag "Doom [LARGE]" "doomemacs-large")
                 (const :tag "Doom Gruv" "doomemacs-gruv")
                 (const :tag "Doom Gruv [LARGE]" "doomemacs-gruv-large"))
  :group 'presence)

(defcustom presence-boring-buffers-regexp-list '("^ "
                                               "\\\\*Messages\\\\*")
  "A list of regexp's to match boring buffers.
When visiting a boring buffer, it will not show in the presence presence."
  :type '(repeat regexp)
  :group 'presence)

;;;###autoload
(define-minor-mode presence-mode
  "Global minor mode for displaying Rich Presence in Discord."
  nil nil nil
  :require 'presence
  :global t
  :group 'presence
  :after-hook
  (progn
    (cond
     (presence-mode
      (presence--enable))
     (t
      (presence--disable)))))

(defvar presence--editor-name
  (cond
   ((boundp 'spacemacs-version) "Spacemacs")
   ((boundp 'doom-version) "DOOM Emacs")
   (t "Emacs"))
  "The name to use to represent the current editor.")

(defvar presence--discord-ipc-pipe "discord-ipc-0"
  "The name of the discord IPC pipe.")

(defvar presence--update-presence-timer nil
  "Timer which periodically updates Discord Rich Presence.
nil when presence is not active.")

(defvar presence--reconnect-timer nil
  "Timer used by presence to attempt connection periodically, when active but disconnected.")

(defvar presence--sock nil
  "The process used to communicate with Discord IPC.")

(defvar presence--last-known-position (count-lines (point-min) (point))
  "Last known position (line number) recorded by presence.")

(defvar presence--last-known-buffer-name (buffer-name)
  "Last known buffer recorded by presence.")

(defvar presence--stdpipe-path (expand-file-name
                              "stdpipe.ps1"
                              (file-name-directory (file-truename buffer-file-name)))
  "Path to the 'stdpipe' script.
On Windows, this script is used as a proxy for the Discord named pipe.
Unused on other platforms.")

(defvar presence--idle-status nil
  "Current idle status.")

(defun presence--make-process ()
  "Make the asynchronous process that communicates with Discord IPC."
  (let ((default-directory "~/"))
    (cl-case system-type
      (windows-nt
       (make-process
        :name "*presence-sock*"
        :command (list
                  "PowerShell"
                  "-NoProfile"
                  "-ExecutionPolicy" "Bypass"
                  "-Command" presence--stdpipe-path "." presence--discord-ipc-pipe)
        :connection-type 'pipe
        :sentinel 'presence--connection-sentinel
        :filter 'presence--connection-filter
        :noquery t))
      (t
       (make-network-process
        :name "*presence-sock*"
        :remote (expand-file-name
                 presence--discord-ipc-pipe
                 (file-name-as-directory
                  (or (getenv "XDG_RUNTIME_DIR")
                      (getenv "TMPDIR")
                      (getenv "TMP")
                      (getenv "TEMP")
                      "/tmp")))
        :sentinel 'presence--connection-sentinel
        :filter 'presence--connection-filter
        :noquery t)))))

(defun presence--enable ()
  "Called when variable ‘presence-mode’ is enabled."
  (setq presence--startup-time (string-to-number (format-time-string "%s" (current-time))))
  (unless (presence--resolve-client-id)
    (warn "presence: no presence-client-id available"))
  (when (eq system-type 'windows-nt)
    (unless (executable-find "powershell")
      (warn "presence: powershell not available"))
    (unless (file-exists-p presence--stdpipe-path)
      (warn "presence: 'stdpipe' script does not exist (%s)" presence--stdpipe-path)))
  (when presence-idle-timer
    (run-with-idle-timer
     presence-idle-timer t 'presence--start-idle))

  ;;Start trying to connect
  (presence--start-reconnect))

(defun presence--disable ()
  "Called when variable ‘presence-mode’ is disabled."
  ;;Cancel updates
  (presence--cancel-updates)
  ;;Cancel any reconnect attempt
  (presence--cancel-reconnect)

  ;;If we're currently connected
  (when presence--sock
    ;;Empty our presence
    (presence--empty-presence))

  ;;Stop running idle hook
  (cancel-function-timers 'presence--start-idle)

  (presence--disconnect))

(defun presence--empty-presence ()
  "Sends an empty presence for when presence is disabled."
  (let* ((nonce (format-time-string "%s%N"))
         (presence
          `(("cmd" . "SET_ACTIVITY")
            ("args" . (("activity" . nil)
                       ("pid" . ,(emacs-pid))))
            ("nonce" . ,nonce))))
    (presence--send-packet 1 presence)))

(defun presence--resolve-client-id ()
  "Evaluate `presence-client-id' and return the client ID to use."
  (cl-typecase presence-client-id
    (null
     nil)
    (string
     presence-client-id)
    (function
     (funcall presence-client-id))))

(defun presence--resolve-icon-base (icon)
  "Evaluate `presence-icon-base' and return the URL to use.
Argument ICON the name of the icon we're resolving."
  (cl-typecase presence-icon-base
    (null
     nil)
    (string
     (concat presence-icon-base icon ".png"))
    (function
     (funcall presence-icon-base icon))))

(defun presence--connection-sentinel (process evnt)
  "Track connection state change on Discord connection.
Argument PROCESS The process this sentinel is attached to.
Argument EVNT The event which triggered the sentinel to run."
  (cl-case (process-status process)
    ((closed exit)
     (presence--handle-disconnect))
    (t)))

(defun presence--connection-filter (process evnt)
  "Track incoming data from Discord connection.
Argument PROCESS The process this filter is attached to.
Argument EVNT The available output from the process."
  (presence--start-updates))

(defun presence--connect ()
  "Connects to the Discord socket."
  (or presence--sock
      (ignore-errors
        (unless presence-quiet
          (message "presence: attempting reconnect.."))
        (setq presence--sock (presence--make-process))
        (condition-case nil
            (presence--send-packet 0 `(("v" . 1) ("client_id" . ,(presence--resolve-client-id))))
          (error
           (delete-process presence--sock)
           (setq presence--sock nil)))
        presence--sock)))

(defun presence--disconnect ()
  "Disconnect presence."
  (when presence--sock
    (delete-process presence--sock)
    (setq presence--sock nil)))

(defun presence--reconnect ()
  "Attempt to reconnect presence."
  (when (presence--connect)
    ;;Reconnected.
    ;; Put a pending message unless we already got first handshake
    (unless (or presence--update-presence-timer presence-quiet)
      (message "presence: connecting..."))
    (presence--cancel-reconnect)))

(defun presence--start-reconnect ()
  "Start attempting to reconnect."
  (unless (or presence--sock presence--reconnect-timer)
    (setq presence--reconnect-timer (run-at-time 0 15 'presence--reconnect))))

(defun presence--cancel-reconnect ()
  "Cancels any ongoing reconnection attempt."
  (when presence--reconnect-timer
    (cancel-timer presence--reconnect-timer)
    (setq presence--reconnect-timer nil)))

(defun presence--handle-disconnect ()
  "Handles reconnecting when socket disconnects."
  (unless presence-quiet
    (message "presence: disconnected by remote host"))
  ;;Stop updating presence for now
  (presence--cancel-updates)
  (setq presence--sock nil)
  ;;Start trying to reconnect
  (when presence-mode
    (presence--start-reconnect)))

(defun presence--send-packet (opcode obj)
  "Packs and sends a packet to the IPC server.
Argument OPCODE OP code to send.
Argument OBJ The data to send to the IPC server."
  (let* ((jsonstr
          (encode-coding-string
           (json-encode obj)
           'utf-8))
         (datalen (length jsonstr))
         (message-spec
          `((:op u32r)
            (:len u32r)
            (:data str ,datalen)))
         (packet
          (bindat-pack
           message-spec
           `((:op . ,opcode)
             (:len . ,datalen)
             (:data . ,jsonstr)))))
    (process-send-string presence--sock packet)))

(defun presence--test-match-p (test mode)
  "Test `MODE' against `TEST'.
if `test' is a symbol, it is compared directly to `mode'.
if `test' is a string, it is a regex to compare against the name of `mode'."
  (cl-typecase test
    (symbol (eq test mode))
    (string (string-match-p test (symbol-name mode)))))

(defun presence--entry-value (entry mode)
  "Test `ENTRY' against `MODE'.  Return the value of `ENTRY'.
`entry' is a cons who's `car' is `presence--test-match-p' with `mode''
When `mode' matches, if the `cdr' of `entry' is a string, return that,
otherwise if it is a function, call it with `mode' and return that value."
  (when (presence--test-match-p (car entry) mode)
    (let ((mapping (cdr entry)))
      (cl-typecase mapping
        (string mapping)
        (function (funcall mapping mode))))))

(defun presence--find-mode-entry (alist mode)
  "Get the first entry in `ALIST' matching `MODE'.
`alist' Should be an alist like `presence-mode-icon-alist' where each value is
 either a string,or a function of one argument `mode'.
 If it is a function, it should return a string, or nil if no match."
  (let ((cell alist)
        (result nil))
    (while cell
      (setq result (presence--entry-value (car cell) mode)
            cell (if result nil (cdr cell))))
    result))

(defun presence--editor-icon ()
  "The icon to use to represent the current editor."
  (cond
   ((progn presence-editor-icon) (presence--resolve-icon-base presence-editor-icon))
   ((boundp 'spacemacs-version) (presence--resolve-icon-base "emacs"))
   ((boundp 'doom-version) (presence--resolve-icon-base "doomemacs"))
   (t (presence--resolve-icon-base "emacs"))))

(defun presence--mode-icon ()
  "Figure out what icon to use for the current major mode.
If an icon is mapped by `presence-mode-icon-alist', then that is used.
Otherwise, if the mode is a derived mode, try to find an icon for it.
If no icon is available, use the default icon."
  (let ((mode major-mode)
        (ret (presence--editor-icon)))
    (while mode
      (if-let ((icon (presence--find-mode-entry presence-mode-icon-alist mode)))
          (setq ret (presence--resolve-icon-base icon)
                mode nil)
        (setq mode (get mode 'derived-mode-parent))))
    ret))

(defun presence--mode-text ()
  "Figure out what text to use for the current major mode.
If an icon is mapped by `presence-mode-text-alist', then that is used.
Otherwise, if the mode is a derived mode, try to find text for its parent,
If no text is available, use the value of `mode-name'."
  (let ((mode major-mode)
        (ret mode-name))
    (while mode
      (if-let ((text (presence--find-mode-entry presence-mode-text-alist mode)))
          (setq ret text
                mode nil)
        (setq mode (get mode 'derived-mode-parent))))
    (unless (stringp ret)
      (setq ret (format-mode-line ret)))
    ret))

(defun presence--mode-icon-and-text ()
  "Obtain the icon & text to use for the current major mode.
\((\"large_text\" . <text>)
  (\"large_image\" . <icon-name>)
  (\"small_text\" . <text>)
  (\"small_image\" . <icon-name>))"
  (let ((text (presence--mode-text))
        (icon (presence--mode-icon))
        large-text large-image
        small-text small-image)
    (cond
     (presence-use-major-mode-as-main-icon
      (setq large-text text
            large-image icon
            small-text (if presence--idle-status "Idle" presence--editor-name)
            small-image (if presence--idle-status (presence--resolve-icon-base "idle") (presence--editor-icon))))
     (t
      (setq large-text (if presence--idle-status "Idle" presence--editor-name)
            large-image (if presence--idle-status (presence--resolve-icon-base "idle") (presence--editor-icon))
            small-text text
            small-image icon)))
    (cond
     (presence-show-small-icon
      (list
       (cons "large_text" large-text)
       (cons "large_image" large-image)
       (cons "small_text" small-text)
       (cons "small_image" small-image)))
     (t
      (list
       (cons "large_text" large-text)
       (cons "large_image" large-image)
       (cons "small_text" small-text))))))

(defun presence-buffer-details-format ()
  "Return the buffer details string shown on discord."
  (format "Working on %s" (buffer-name)))

(defun presence--details-and-state ()
  "Obtain the details and state to use for Discord's Rich Presence."
  (let ((activity (if presence-display-buffer-details
                      (if presence-display-line-numbers
                          (list
                           (cons "details" (funcall presence-buffer-details-format-function))
                           (cons "state" (format "Currently at line %s"
                                                 (format-mode-line "%l")
                                                 (+ 1 (count-lines (point-min) (point-max))))))
                        (list
                         (cons "details" (funcall presence-buffer-details-format-function))))
                    (list
                     (cons "details" "Editing")
                     (cons "state" (presence--mode-text))))))
    (when presence-display-elapsed
      (push (list "timestamps" (cons "start" presence--startup-time)) activity))
    activity))

(defun presence--set-presence ()
  "Set presence."
  (let* ((activity
          `(("assets" . (,@(presence--mode-icon-and-text)))
            ,@(presence--details-and-state)))
         (nonce (format-time-string "%s%N"))
         (presence
          `(("cmd" . "SET_ACTIVITY")
            ("args" . (("activity" . ,activity)
                       ("pid" . ,(emacs-pid))))
            ("nonce" . ,nonce))))
    (presence--send-packet 1 presence)))

(defun presence--buffer-boring-p (buffer-name)
  "Return non-nil if `BUFFER-NAME' is non-boring per `PRESENCE-BORING-BUFFERS-REGEXP-LIST'."
  (let ((cell presence-boring-buffers-regexp-list)
        (result nil))
    (while cell
      (if (string-match-p (car cell) buffer-name)
          (setq result t
                cell nil)
        (setq cell (cdr cell))))
    result))

(defun presence--find-non-boring-window ()
  "Try to find a live window displaying a non-boring buffer."
  (let ((cell (window-list))
        (result nil))
    (while cell
      (let ((window (car cell)))
        (if (not (presence--buffer-boring-p (buffer-name (window-buffer window))))
            (setq result window
                  cell nil)
          (setq cell (cdr cell)))))
    result))

(defun presence--try-update-presence (new-buffer-name new-buffer-position)
  "Try updating presence with `NEW-BUFFER-NAME' and `NEW-BUFFER-POSITION' while handling errors and disconnections."
  (setq presence--last-known-buffer-name new-buffer-name
        presence--last-known-position new-buffer-position)
  (condition-case err
      ;;Try and set the presence
      (presence--set-presence)
    (error
     (message "presence: error setting presence: %s" (error-message-string err))
     ;;If we hit an error, cancel updates
     (presence--cancel-updates)
     ;; Disconnect
     (presence--disconnect)
     ;; and try reconnecting
     (presence--start-reconnect))))

(defun presence--update-presence ()
  "Conditionally update presence by testing the current buffer/line.
If there is no 'previous' buffer attempt to find a non-boring buffer to initialize to."
  (if (= presence--last-known-position -1)
      (when-let ((window (presence--find-non-boring-window)))
        (with-current-buffer (window-buffer window)
          (presence--try-update-presence (buffer-name) (count-lines (point-min) (point)))))
    (let ((new-buffer-name (buffer-name (current-buffer))))
      (unless (presence--buffer-boring-p new-buffer-name)
        (let ((new-buffer-position (count-lines (point-min) (point))))
          (unless (and (string= new-buffer-name presence--last-known-buffer-name)
                       (= new-buffer-position presence--last-known-position))
            (presence--try-update-presence new-buffer-name new-buffer-position)))))))

(defun presence--start-updates ()
  "Start sending periodic update to Discord Rich Presence."
  (unless presence--update-presence-timer
    (unless presence-quiet
      (message "presence: connected. starting updates"))
    ;;Start sending updates now that we've heard from discord
    (setq presence--last-known-position -1
          presence--last-known-buffer-name ""
          presence--update-presence-timer (run-at-time 0 presence-refresh-rate 'presence--update-presence))))

(defun presence--cancel-updates ()
  "Stop sending periodic update to Discord Rich Presence."
  (when presence--update-presence-timer
    (cancel-timer presence--update-presence-timer)
    (setq presence--update-presence-timer nil)))

(defun presence--start-idle ()
  "Set presence to idle, pause update and timer."
  (unless presence--idle-status
    (unless presence-quiet
      (message (format "presence: %s" presence-idle-message)))

    ;;hacky way to stop updates and store elapsed time
    (cancel-timer presence--update-presence-timer)
    (setq presence--startup-time (string-to-number (format-time-string "%s" (time-subtract nil presence--startup-time)))

          presence--idle-status t)

    (let* ((activity
            `(("assets" . (,@(presence--mode-icon-and-text)))
              ("timestamps" ("start" ,@(string-to-number (format-time-string "%s" (current-time)))))
              ("details" . "Idling") ("state" .  ,presence-idle-message)))
           (nonce (format-time-string "%s%N"))
           (presence
            `(("cmd" . "SET_ACTIVITY")
              ("args" . (("activity" . ,activity)
                         ("pid" . ,(emacs-pid))))
              ("nonce" . ,nonce))))
      (presence--send-packet 1 presence))
    (add-hook 'pre-command-hook 'presence--cancel-idle)))

(defun presence--cancel-idle ()
  "Resume presence update and timer."
  (when presence--idle-status
    (remove-hook 'pre-command-hook 'presence--cancel-idle)

    ;;resume timer with elapsed time
    (setq presence--startup-time (string-to-number (format-time-string "%s" (time-subtract nil presence--startup-time)))
          presence--idle-status nil
          ;;hacky way to resume updates
          presence--update-presence-timer nil)
    (presence--start-updates)

    (unless presence-quiet
      (message "presence: welcome back"))))


(provide 'presence)
;;; presence.el ends here
