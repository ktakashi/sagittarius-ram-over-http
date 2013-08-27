;;; -*- mode:scheme; coding:utf-8; -*-
;;;
;;; ram-over-http.scm - RAM over HTTP
;;;
;;;   Copyright (c) 2013  Takashi Kato  <ktakashi@ymail.com>
;;;
;;;   Redistribution and use in source and binary forms, with or without
;;;   modification, are permitted provided that the following conditions
;;;   are met:
;;;
;;;   1. Redistributions of source code must retain the above copyright
;;;      notice, this list of conditions and the following disclaimer.
;;;
;;;   2. Redistributions in binary form must reproduce the above copyright
;;;      notice, this list of conditions and the following disclaimer in the
;;;      documentation and/or other materials provided with the distribution.
;;;
;;;   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;;;   "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;;;   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;;;   A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
;;;   OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;;;   SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
;;;   TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
;;;   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
;;;   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;;;   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;;;   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;;;
(library (ram-oever-http)
    (export start-session)
    (import (rnrs)
	    (sagittarius)
	    (sagittarius control)
	    (rfc http)
	    (rfc uri)
	    (rfc uuid)
	    (tlv)
	    (srfi :13 strings)
	    (pcsc shell commands))

  (define-constant +protocol+ "globalplatform-remote-admin/1.0")
  (define-constant +initial-content-type+ "application/octet-stream")
  (define-constant +content-type+
    "application/vnd.globalplatform.card-content-mgt-response;version=1.0")

  (define +remote-apdu+ (list (lambda (in b) (values b #f))  read-ber-length))

  (define tlv-parser (make-tlv-parser +remote-apdu+))

  (define (remote-apdu->apdu-list remote-apdu)
    ;; do some check
    (let1 len (bytevector-length remote-apdu)
      (unless (= (bytevector-u8-ref remote-apdu 0) #xAE)
	(error 'remote-apdu "Not a Command TLV" remote-apdu))
      (unless (= (bytevector-u8-ref remote-apdu 1) #x00)
	(error 'remote-apdu "Bad Request ILD indicator" remote-apdu))
      (unless (= (bytevector-u16-ref remote-apdu (- len 2) (endianness big)) #x00)
	(error 'remote-apdu "Request not ending wit two trailing #x00"
	       remote-apdu))
      (let1 tlv* (read-tlv (open-bytevector-input-port 
			    (bytevector-copy remote-apdu 2 (- len 2)))
			   tlv-parser)
	(map tlv-data tlv*))))

  (define (start-session url imsi :key (headers '()) (trace #f))
    (define (assoc-ci target headers) (assoc target headers string-ci=?))
    (define (decompose-url url)
      (let-values (((s u host port path query frag) (uri-parse url)))
	(values (if port (string-append host ":" (number->string port)) host)
		(format "~a~a~a" path
			(or (and query (string-append "?" query)) "")
			(or (and frag (string-append "#" frag)) "")))))
    (define (one-session server path data content-type header)
      (let-values (((status headers body)
		    (apply http-post server path data
			   :receiver (http-binary-receiver)
			   :x-admin-from imsi
			   :x-admin-protocol +protocol+
			   :content-type content-type header)))
	;; it can send 204 status ...
	(if (char=? (string-ref status 0) #\2)
	    (let (#;(aid (assoc-ci "x-admin-targeted-application" headers))
		  (url (assoc-ci "x-admin-next-uri" headers)))
	      ;; todo run apdu command
	      (values (and url (cadr url)) body))
	    (values #f #f))))

    (define (send-apdu apdu) 
      (tlv->bytevector (make-tlv-unit #x23 (invoke-command send-apdu apdu))))

    (define (encode-apdu response*)
      (bytevector-concatenate (append (cons #vu8(#xAF #x80) response*)
				      '(#vu8(0 0)))))

    (define (do-session)
      (let-values (((server path) (decompose-url url)))
	(let loop ((response #vu8()) 
		   (url "")
		   (content-type +initial-content-type+)
		   (headers headers))
	  (let-values (((next-url command) 
			(one-session server (string-append path url)
				     response content-type headers)))
	    (when (and next-url (not (zero? (bytevector-length command))))
	      (let1 apdu* (remote-apdu->apdu-list command)
		;; handle APDU error. RAM over HTTP has multiple error
		;; code but we only send security-error when apdu command
		;; execution failed.
		(let-values (((response status)
			      (guard (e (#t (values #vu8() "security-error")))
				(values (encode-apdu (map send-apdu apdu*))
					"ok"))))
		  (loop response next-url +content-type+ 
			`(:x-admin-script-status ,status)))))))))
    
    (unwind-protect
	(begin (invoke-command establish-context)
	       (invoke-command card-connect)
	       (when trace (invoke-command trace-on))
	       (do-session))
      (invoke-command release-context))
    )

)