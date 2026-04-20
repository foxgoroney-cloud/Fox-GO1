importScripts("https://www.gstatic.com/firebasejs/7.20.0/firebase-app.js");
importScripts("https://www.gstatic.com/firebasejs/7.20.0/firebase-messaging.js");

firebase.initializeApp({
  apiKey: "AIzaSyCO56AZ8at4zENB5gUxSitZ0yk1tBxopnw",
  authDomain: "foxdelivery-54b9a.firebaseapp.com",
  projectId: "foxdelivery-54b9a",
  storageBucket: "foxdelivery-54b9a.firebasestorage.app",
  messagingSenderId: "1025664471197",
});

const messaging = firebase.messaging();

// Optional:
messaging.onBackgroundMessage((message) => {
  console.log("onBackgroundMessage", message);
});
