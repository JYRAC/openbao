// pubgate: OpenBao の公開側(0.0.0.0:8200)の、入口。
//
// 既定(閉じている): GET/HEAD /healthz だけに、200 を返す(Render Free を眠らせないための、外からの確認用)。
//   それ以外は、OpenBao に、まったく届けずに、404 を返す。OpenBao の本体の API は、NetBird 経由(8210)だけ。
// OPENBAO_PUBLIC=open(緊急の、一時的な再開): すべてを、OpenBao 本体(127.0.0.1:8205)に流す。以前の公開側と同じ。
//   使い終わったら、OPENBAO_PUBLIC を消して、再デプロイする(OpenBao は、再デプロイで封印される。手動で unseal)。
//
// 標準ライブラリのみ。
package main

import (
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"sync/atomic"
	"time"
)

func main() {
	listen := os.Getenv("PUBGATE_LISTEN")
	if listen == "" {
		listen = "0.0.0.0:8200"
	}
	upstream := os.Getenv("PUBGATE_UPSTREAM")
	if upstream == "" {
		upstream = "http://127.0.0.1:8205"
	}

	var handler http.Handler
	if os.Getenv("OPENBAO_PUBLIC") == "open" {
		u, err := url.Parse(upstream)
		if err != nil {
			log.Fatalf("PUBGATE: PUBGATE_UPSTREAM が不正です: %v", err)
		}
		handler = httputil.NewSingleHostReverseProxy(u)
		log.Printf("PUBGATE mode=open: 公開側を、一時的に開いています(緊急用)。終わったら、OPENBAO_PUBLIC を消して再デプロイしてください")
	} else {
		var blocked uint64
		go func() { // 拒否した件数だけを、1 分ごとに、ログに残す(中身は、残さない)
			var last uint64
			for range time.Tick(time.Minute) {
				n := atomic.LoadUint64(&blocked)
				if n != last {
					log.Printf("PUBGATE closed: この 1 分に拒否した要求 %d 件(合計 %d)", n-last, n)
					last = n
				}
			}
		}()
		handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if (r.Method == http.MethodGet || r.Method == http.MethodHead) && r.URL.Path == "/healthz" {
				w.Header().Set("Content-Type", "text/plain; charset=utf-8")
				w.Header().Set("Cache-Control", "no-store")
				_, _ = w.Write([]byte("ok\n"))
				return
			}
			atomic.AddUint64(&blocked, 1)
			http.NotFound(w, r)
		})
		log.Printf("PUBGATE mode=closed: 公開側は、/healthz だけに応答します")
	}

	srv := &http.Server{
		Addr:              listen,
		Handler:           handler,
		ReadHeaderTimeout: 10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}
	log.Fatal(srv.ListenAndServe())
}
