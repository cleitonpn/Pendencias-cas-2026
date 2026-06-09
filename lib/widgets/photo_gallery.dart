import 'package:flutter/material.dart';

/// Horizontal strip of photo thumbnails (from network URLs). Tapping a photo
/// opens a fullscreen, zoomable viewer.
class PhotoStrip extends StatelessWidget {
  final List<String> urls;
  const PhotoStrip({super.key, required this.urls});

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => _PhotoViewer(urls: urls, initial: i)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              urls[i],
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              loadingBuilder: (c, child, progress) => progress == null
                  ? child
                  : Container(
                      width: 72,
                      height: 72,
                      color: Colors.grey.shade200,
                      child: const Center(
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))),
                    ),
              errorBuilder: (c, e, s) => Container(
                width: 72,
                height: 72,
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoViewer extends StatelessWidget {
  final List<String> urls;
  final int initial;
  const _PhotoViewer({required this.urls, required this.initial});

  @override
  Widget build(BuildContext context) {
    final controller = PageController(initialPage: initial);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: PageView.builder(
        controller: controller,
        itemCount: urls.length,
        itemBuilder: (context, i) => InteractiveViewer(
          minScale: 0.8,
          maxScale: 4,
          child: Center(
            child: Image.network(
              urls[i],
              fit: BoxFit.contain,
              errorBuilder: (c, e, s) => const Icon(Icons.broken_image,
                  color: Colors.white54, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}
