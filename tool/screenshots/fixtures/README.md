# Render fixtures (test-only, not bundled)

`sample_face.jpg` stands in for a user's own scan selfie in design renders
(Unsplash photo-1521146764736-56c929d59c83, Unsplash License).

`sample_face.json` holds real facial landmarks for that photo, detected with
Google MediaPipe Face Mesh and grouped under ML Kit's contour names, in the
same `FaceGeometry` format the app stores at capture time. On a phone the
landmarks come from ML Kit during the scan.
