;;; anki-helper.el --- help you to create vocabulary card in Anki

;; Copyright (C) 2019-2019 DarkSun <lujun9972@gmail.com>.

;; Author: DarkSun <lujun9972@gmail.com>
;; Keywords: lisp, anki, translator, chinese
;; Package: pdf-anki-helper
;; Version: 1.0
;; Package-Requires: ((emacs "24.3") (youdao-dictionary "20180714") (AnkiConnect "1.0"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Source code
;;
;; anki-helper's code can be found here:
;;   http://github.com/lujun9972/anki-helper.el

;;; Commentary:

;; anki-helper is a plugin that help you to create vocabulary card in Anki
;; Just select the sentence then execute =M-x anki-helper=


;;; Code:

(require 'pdf-view)
(require 'youdao-dictionary)
(require 'AnkiConnect)

(defgroup pdf-anki-helper nil
  ""
  :prefix "anki-helper"
  :group 'tools
  :link '(url-link :tag "Github" "https://github.com/lujun9972/pdf-anki-helper.el"))

(defcustom anki-helper-deck-name ""
  "Which deck would the word stored"
  :type 'string)

(defcustom anki-helper-model-name ""
  "Specify the model name"
  :type 'string)

(defcustom anki-helper-field-alist nil
  "指定field的对应关系"
  :type 'string)

(defcustom anki-helper-audio-fileds nil
  "Specify fields used to store audio"
  :type 'list)

(defcustom anki-helper-before-addnote-functions nil
  "List of hook functions run before add note.

The functions should accept those arguments:
+ expression(单词)
+ sentence(单词所在句子)
+ sentence_bold(单词所在句子,单词加粗)
+ translation(翻译的句子)
+ glossary(单词释义)
+ us-phonetic(美式发音)
+ uk-phonetic(英式发音)"
  :type 'hook)

(defcustom anki-helper-after-addnote-functions nil
  "List of hook functions run after add note.

The functions should accept those arguments:
+ expression(单词)
+ sentence(单词所在句子)
+ sentence_bold(单词所在句子,单词加粗)
+ translation(翻译的句子)
+ glossary(单词释义)
+ us-phonetic(美式发音)
+ uk-phonetic(英式发音)"
  :type 'hook)

;;;###autoload
(defun anki-helper-set-ankiconnect ()
  ""
  (interactive)
  (let ((deck-names (AnkiConnect-DeckNames))
        (model-names (AnkiConnect-ModelNames)))
    (setq anki-helper-deck-name (completing-read "Select the Deck Name:" deck-names))
    (setq anki-helper-model-name (completing-read "Select the Model Name:" model-names))
    (setq anki-helper-field-alist nil)
    (let* ((skip-field " ")
           (fields (cons skip-field (AnkiConnect-ModelFieldNames anki-helper-model-name))))
      (dolist (element '(expression glossary us-phonetic uk-phonetic sentence sentence_bold translation audio))
        (let* ((prompt (format "%s" element))
               (field (completing-read prompt fields)))
          (unless (string= field skip-field)
            (setq fields (remove field fields))
            (if (equal 'audio element)
                (pushnew field anki-helper-audio-fileds)
              (add-to-list 'anki-helper-field-alist (cons field element)))))))))

(defun anki-helper--get-pdf-text ()
  "Get the text in pdf mode."
  (pdf-view-assert-active-region)
  (let* ((txt (pdf-view-active-region-text))
         (txt (string-join txt "\n")))
    (replace-regexp-in-string "[\r\n]+" " " txt)))

(defun anki-helper--get-normal-text ()
  "Get the text in normal mode"
  (let ((txt (if (region-active-p)
                 (buffer-substring-no-properties (region-beginning) (region-end))
               (or (sentence-at-point)
                   (thing-at-point 'line)))))
    (replace-regexp-in-string "[\r\n]+" " " txt)))

(defun anki-helper--get-text ()
  "Get the region text"
  (if (derived-mode-p 'pdf-view-mode)
      (anki-helper--get-pdf-text)
    (anki-helper--get-normal-text)))

(defun anki-helper--select-word-in-string (str)
  "Select word in `STR'."
  (let ((words (split-string str "[ \f\t\n\r\v,.:?;\"<>]+")))
    (completing-read "请选择单词: " words)))

(defun anki-helper--get-word ()
  (unless (derived-mode-p 'pdf-view-mode)
    (word-at-point)))

;;;###autoload
(defun anki-helper (&optional sentence word)
  (interactive)
  (let* ((sentence (or sentence (anki-helper--get-text))) ; 原句
         (word (or word (anki-helper--get-word) (anki-helper--select-word-in-string sentence)))
         (sentence_bold (replace-regexp-in-string (concat "\\b" (regexp-quote word) "\\b")
                                                  (lambda (word)
                                                    (format "<b>%s</b>" word))
                                                  sentence)) ; 粗体标记的句子
         (json (youdao-dictionary--request sentence))
         (translation (aref (assoc-default 'translation json) 0)) ; 翻译
         (json (youdao-dictionary--request word))
         (explains (youdao-dictionary--explains json))
         (basic (cdr (assoc 'basic json)))
         (expression (cdr (assoc 'query json))) ; 拼写
         (prompt (format "%s(%s):" translation expression))
         (glossary (completing-read prompt (mapcar #'identity explains))) ; 释义
         (us-phonetic (cdr (assoc 'us-phonetic basic))) ; 美式发音
         (uk-phonetic (cdr (assoc 'uk-phonetic basic))) ; 英式发音
         (fileds (mapcar #'car anki-helper-field-alist))
         (symbols (mapcar #'cdr anki-helper-field-alist))
         (values (mapcar #'symbol-value symbols))
         (fields (cl-mapcar #'cons fileds values)))
    (run-hook-with-args 'anki-helper-before-addnote-functions expression sentence sentence_bold translation glossary us-phonetic uk-phonetic)
    (if anki-helper-audio-fileds
        (let* ((audio-url (youdao-dictionary--format-voice-url word)) ; audio
               (audio-filename (format "youdao-%s.mp3" (md5 audio-url)))
               (audio-fileds (apply #'vector anki-helper-audio-fileds))
               (audio `(("url" . ,audio-url)
                        ("filename" . ,audio-filename)
                        ("fields" . ,audio-fileds))))
          (AnkiConnect-AddNote anki-helper-deck-name anki-helper-model-name fields audio))
      (AnkiConnect-AddNote anki-helper-deck-name anki-helper-model-name fields))
    (run-hook-with-args 'anki-helper-after-addnote-functions expression sentence sentence_bold translation glossary us-phonetic uk-phonetic)))

(provide 'anki-helper)

;;; anki-helper.el ends here
